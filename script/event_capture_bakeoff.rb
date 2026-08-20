#!/usr/bin/env ruby
# frozen_string_literal: true

# Event-extraction bake-off for the user-event-capture funnel. What it measured, and
# the decision it settled: docs/user-event-capture-provider-evaluation.md.
#
# Runs ONE prompt over six real sample images through every provider you have a
# key for, then scores the results against event_capture_bakeoff_truth.json.
# The question it answers: can a Swiss/EU-hosted model read a Bern concert poster
# well enough that we don't have to send images to a US provider?
#
# Stdlib only — no bundler, nothing to install. Providers with no key are SKIPPED,
# so you can run this with one key today and re-run as the others arrive.
#
#   ANTHROPIC_API_KEY=sk-ant-...   MISTRAL_API_KEY=...
#   INFOMANIAK_API_TOKEN=...       INFOMANIAK_PRODUCT_ID=12345
#
#   ruby script/event_capture_bakeoff.rb                    # every provider with a key
#   ruby script/event_capture_bakeoff.rb --only mistral     # just one
#   ruby script/event_capture_bakeoff.rb --no-crop          # send the WhatsApp chrome too
#   ruby script/event_capture_bakeoff.rb --list-infomaniak  # discover Infomaniak model IDs
#
# The sample images are NOT in the repo and must not be — two are WhatsApp
# screenshots containing other people's names and phone numbers. They're read
# from ~/Downloads (override with BAKEOFF_IMAGE_DIR). Everything the script
# writes — the prepped images actually uploaded, and the raw model responses —
# goes to tmp/event_capture_bakeoff/, which is gitignored. Keep it that way.

require "net/http"
require "uri"
require "json"
require "base64"
require "optparse"
require "fileutils"
require "date"
require "digest"

ROOT       = File.expand_path(__dir__)
IMAGE_DIR  = File.expand_path(ENV.fetch("BAKEOFF_IMAGE_DIR", "~/Downloads"))
OUT        = File.expand_path("../tmp/event_capture_bakeoff", __dir__)
PREPPED    = File.join(OUT, "prepped")
TRUTH      = JSON.parse(File.read(File.join(ROOT, "event_capture_bakeoff_truth.json")))
TODAY      = Time.now.strftime("%Y-%m-%d")

# The six samples, in ascending difficulty-ish order.
IMAGES = TRUTH.keys.reject { |k| k.start_with?("_") }

# WhatsApp screenshots carry other people's names and phone numbers in the
# chrome. Crop it off before anything leaves the machine. Fractions are
# [top, bottom] of the image height to remove.
CHROME_CROP = {
  "IMG_2023.PNG" => [0.14, 0.07],
  "IMG_2024.PNG" => [0.11, 0.07]
}.freeze

# Cropping the chrome is not enough for IMG_2024: two senders' names and full
# phone numbers sit INLINE in the message list, mid-image. These bands (as
# fractions of the post-crop height) get painted black. Verified by eye against
# the prepped output — re-check them if you change CHROME_CROP.
REDACT_BANDS = {
  "IMG_2024.PNG" => [[0.000, 0.021],   # sliver of the member list left by the crop
                     [0.267, 0.299],   # sender header row (display name + phone number)
                     [0.880, 0.911],   # second sender header row
                     [0.943, 0.971]]   # a third, clipped at the cut edge
}.freeze

options = { only: nil, crop: true, list_infomaniak: false, prep_only: false,
            limit: nil, runs: 1, json_mode: true, max_long_edge: 1568 }
OptionParser.new do |o|
  o.banner = "Usage: ruby script/event_capture_bakeoff.rb [options]"
  o.on("--only PROVIDER", "anthropic | mistral | infomaniak") { |v| options[:only] = v }
  o.on("--no-crop", "Do NOT strip WhatsApp chrome before sending") { options[:crop] = false }
  o.on("--prep-only", "Prep + sanitize images, open them, send NOTHING") { options[:prep_only] = true }
  o.on("--limit N", Integer, "Only run the first N images (debugging)") { |v| options[:limit] = v }
  o.on("--runs N", Integer, "Repeat the whole set N times (stability testing)") { |v| options[:runs] = v }
  o.on("--no-json-mode", "Drop response_format — some compat layers reject it") { options[:json_mode] = false }
  o.on("--list-infomaniak", "List Infomaniak model IDs and exit") { options[:list_infomaniak] = true }
end.parse!

# ---------------------------------------------------------------- the prompt

SYSTEM = <<~TXT
  You extract concert/event listings from images for a Swiss (Bern-area) event
  site. Input is a photographed poster, a flyer, or a screenshot of a chat
  message. Text is usually German, sometimes French or English.

  Today is #{TODAY}.

  THE EVIDENCE RULE — this governs everything below.

  Every `date` and every `place` you return MUST be copied from text you can
  actually read in the image, and you must quote that text verbatim in
  `date_evidence` / `place_evidence`. If you cannot quote it, the field is null
  and the evidence field is null. Never supply a value you cannot cite.

  You are NOT being asked to identify the venue. You are being asked to
  transcribe what the image says. A plausible guess is worse than null: a wrong
  venue silently creates a fake location in our database, whereas a null is
  simply completed by a human in one tap.

  Rules:

  1. ONE IMAGE MAY ADVERTISE SEVERAL EVENTS. A poster listing two dates is two
     events. A festival timetable with three time slots is three events. Return
     every one of them.

  2. CHAT UI IS NOT EVENT DATA. In a messaging screenshot, ignore completely:
     day separators ("Saturday", "Yesterday", "Sunday"), message timestamps
     (10:29, 13:43), sender names and phone numbers, reactions, unread badges,
     the status bar. A "Saturday" divider tells you when the MESSAGE was sent.
     It NEVER tells you when the event happens. If the only date-like thing in a
     screenshot is chat chrome, the event has NO date: return null.

  3. Most posters state no year. Resolve a bare date ("26.8.", "Sa. 08.08.") to
     the nearest occurrence. If a weekday is printed, use it as a checksum —
     "Donnerstag 20 August" only fits a year in which 20 August is a Thursday.
     Do NOT roll a past date forward to next year; return the date as printed
     resolves.

  4. `place` is the VENUE OR LOCATION, transcribed exactly as printed. Watch out:
     - The largest text on a poster is usually the ARTIST, not the venue.
     - A band name is not a venue.
     - "auf der Dachterrasse" / "im Park" describes where inside a place — the
       place itself is the name printed elsewhere on the poster.
     - Never substitute a venue you happen to know exists in that city. If the
       image says "ZAR", the answer is "ZAR" — not a café with a similar name.
     - Copy spelling exactly, including K vs C and umlauts. We match these
       against a venue database; one wrong letter means no match.

  5. `city` / `canton` ONLY from something in the image: a street address, a
     postcode, a neighbourhood name, a URL. Otherwise null. Do not guess "Bern"
     because the image looks Swiss.

  6. Read URLs — a venue is often identifiable only from a link. Put the event
     link in source_url.

  7. `genres` only if the image names them. Do not classify the music yourself.
     If a genre line is cut off mid-word, omit it rather than guessing the rest.

  8. `title` is the act or event name. Transcribe unfamiliar names character by
     character — these are small local acts you will not recognise, so do not
     "correct" a name toward one that sounds more familiar.

  FORMATS — these are strict:
    date  exactly YYYY-MM-DD, e.g. "2026-08-20". Never a datetime, never
          "20.08.2026", never the poster's own wording. The evidence field is
          where the original wording goes.
    time  exactly HH:MM on a 24-hour clock, e.g. "20:00". "20 Uhr" becomes
          "20:00"; "19.30h" becomes "19:30". No suffixes, no seconds.
    canton  the 2-letter uppercase code, e.g. "BE".
  A value in any other shape is discarded, so the work is wasted — emit null
  rather than a differently-formatted value.

  Return ONLY a JSON object matching the provided schema. No prose, no markdown.
TXT

USER_TEXT = "Extract every event advertised in this image. JSON only."

# OpenAI-style structured output. Infomaniak rejects the older `json_object` mode
# outright ("no longer supported... please use 'json_schema'"), and a strict schema
# is better anyway: it forces every field to be present, so a model that simply
# omits `date` can't be scored as if it thoughtfully returned null.
# strict mode requires: every property listed in `required`, and additionalProperties false.
EVENT_SCHEMA = {
  name: "extracted_events",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["events"],
    properties: {
      events: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: %w[title date date_evidence time place place_evidence city canton genres source_url],
          properties: {
            title:          { type: %w[string null] },
            date:           { type: %w[string null], description: "YYYY-MM-DD, or null if not legible" },
            date_evidence:  { type: %w[string null],
                              description: "Verbatim text from the image the date was read from. null if the date is null." },
            time:           { type: %w[string null], description: "HH:MM 24h, or null" },
            place:          { type: %w[string null] },
            place_evidence: { type: %w[string null],
                              description: "Verbatim text from the image the place was read from. null if the place is null." },
            city:           { type: %w[string null] },
            canton:         { type: %w[string null], description: "2-letter Swiss canton code" },
            genres:         { type: "array", items: { type: "string" } },
            source_url:     { type: %w[string null] }
          }
        }
      }
    }
  }
}.freeze

# ---------------------------------------------------------------- image prep

def prepare(name, options)
  src = File.join(IMAGE_DIR, name)
  abort "missing image: #{src}" unless File.exist?(src)

  FileUtils.mkdir_p(PREPPED)
  out = File.join(PREPPED, name)
  FileUtils.cp(src, out)

  w, h = `sips -g pixelWidth -g pixelHeight "#{out}"`.scan(/\d+$/).map(&:to_i)

  if options[:crop] && (crop = CHROME_CROP[name])
    top    = (h * crop[0]).round
    bottom = (h * crop[1]).round
    keep   = h - top - bottom
    system("sips", "-c", keep.to_s, w.to_s, "--cropOffset", top.to_s, "0", out,
           out: File::NULL, err: File::NULL)
    h = keep
  end

  long = [w, h].max
  if long > options[:max_long_edge]
    system("sips", "-Z", options[:max_long_edge].to_s, out, out: File::NULL, err: File::NULL)
  end

  if options[:crop] && (bands = REDACT_BANDS[name])
    fw, fh = `sips -g pixelWidth -g pixelHeight "#{out}"`.scan(/\d+$/).map(&:to_i)
    rects = bands.map do |(y0, y1)|
      "rectangle 0,#{(fh * y0).round} #{fw},#{(fh * y1).round}"
    end
    args = ["magick", out, "-fill", "black"]
    rects.each { |r| args += ["-draw", r] }
    args << out
    unless system(*args, out: File::NULL, err: File::NULL)
      warn "  !! ImageMagick missing — #{name} still shows phone numbers. Redact it by hand or drop it."
    end
  end

  [Base64.strict_encode64(File.binread(out)), out]
end

# ---------------------------------------------------------------- HTTP helper

def post_json(url, headers, body, timeout: 180)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = timeout
  req = Net::HTTP::Post.new(uri, headers.merge("content-type" => "application/json"))
  req.body = JSON.generate(body)
  res = http.request(req)
  raise "HTTP #{res.code}: #{res.body}" unless res.code.to_i == 200

  JSON.parse(res.body)
end

# strip ```json fences, then find the outermost {...}
def parse_payload(text)
  cleaned = text.to_s.gsub(/\A\s*```(?:json)?/, "").gsub(/```\s*\z/, "")
  start = cleaned.index("{")
  stop  = cleaned.rindex("}")
  return { "events" => [], "_parse_error" => text.to_s[0, 300] } unless start && stop

  JSON.parse(cleaned[start..stop])
rescue JSON::ParserError => e
  { "events" => [], "_parse_error" => "#{e.message} :: #{text.to_s[0, 300]}" }
end

# ---------------------------------------------------------------- providers

# Resolved once, so the output directory can be named after what was actually run.
MODEL_IDS = {
  "anthropic"  => ENV.fetch("ANTHROPIC_MODEL",  "claude-opus-5"),
  "mistral"    => ENV.fetch("MISTRAL_MODEL",    "mistral-large-latest"),
  "infomaniak" => ENV.fetch("INFOMANIAK_MODEL", "mistralai/Mistral-Small-4-119B-2603")
}.freeze

# $/1M in, $/1M out — for the cost column.
PRICES = {
  "anthropic"  => [5.00, 25.00],
  "mistral"    => [0.50,  1.50],
  "infomaniak" => [0.25,  0.93]
}.freeze

def call_anthropic(b64, _opts)
  model = MODEL_IDS.fetch("anthropic")
  res = post_json(
    "https://api.anthropic.com/v1/messages",
    { "x-api-key" => ENV.fetch("ANTHROPIC_API_KEY"), "anthropic-version" => "2023-06-01" },
    {
      model: model,
      max_tokens: 4000,
      # effort low: this is extraction, not reasoning — the realistic prod setting.
      output_config: { effort: "low" },
      system: SYSTEM,
      messages: [{ role: "user", content: [
        { type: "image", source: { type: "base64", media_type: "image/png", data: b64 } },
        { type: "text", text: USER_TEXT }
      ] }]
    }
  )
  text = res["content"].select { |b| b["type"] == "text" }.map { |b| b["text"] }.join
  [text, res.dig("usage", "input_tokens").to_i, res.dig("usage", "output_tokens").to_i, model]
end

def openai_shaped(url, headers, model, b64, opts = {})
  body = {
    model: model,
    max_tokens: 4000,
    messages: [
      { role: "system", content: SYSTEM },
      { role: "user", content: [
        { type: "text", text: USER_TEXT },
        { type: "image_url", image_url: { url: "data:image/png;base64,#{b64}" } }
      ] }
    ]
  }
  unless opts[:json_mode] == false
    body[:response_format] = { type: "json_schema", json_schema: EVENT_SCHEMA }
  end
  res = post_json(url, headers, body)
  [res.dig("choices", 0, "message", "content"),
   res.dig("usage", "prompt_tokens").to_i,
   res.dig("usage", "completion_tokens").to_i,
   model]
end

def call_mistral(b64, opts)
  openai_shaped("https://api.mistral.ai/v1/chat/completions",
                { "authorization" => "Bearer #{ENV.fetch('MISTRAL_API_KEY')}" },
                MODEL_IDS.fetch("mistral"), b64, opts)
end

def call_infomaniak(b64, opts)
  pid = ENV.fetch("INFOMANIAK_PRODUCT_ID")
  openai_shaped("https://api.infomaniak.com/2/ai/#{pid}/openai/v1/chat/completions",
                { "authorization" => "Bearer #{ENV.fetch('INFOMANIAK_API_TOKEN')}" },
                MODEL_IDS.fetch("infomaniak"), b64, opts)
end

PROVIDERS = {
  "anthropic"  => { ready: -> { ENV["ANTHROPIC_API_KEY"] },
                    call: method(:call_anthropic),
                    need: "ANTHROPIC_API_KEY" },
  "mistral"    => { ready: -> { ENV["MISTRAL_API_KEY"] },
                    call: method(:call_mistral),
                    need: "MISTRAL_API_KEY" },
  "infomaniak" => { ready: -> { ENV["INFOMANIAK_API_TOKEN"] && ENV["INFOMANIAK_PRODUCT_ID"] },
                    call: method(:call_infomaniak),
                    need: "INFOMANIAK_API_TOKEN + INFOMANIAK_PRODUCT_ID" }
}.freeze

# Discovery: from just the token, find the product ID and list the models.
# Sends no image data — only two authenticated GETs.
if options[:list_infomaniak]
  token = ENV.fetch("INFOMANIAK_API_TOKEN") { abort "set INFOMANIAK_API_TOKEN (scope: ai-tools)" }

  get = lambda do |url|
    uri = URI(url)
    http = Net::HTTP.new(uri.host, 443)
    http.use_ssl = true
    res = http.request(Net::HTTP::Get.new(uri, "authorization" => "Bearer #{token}"))
    abort "GET #{url} -> HTTP #{res.code}: #{res.body[0, 400]}" unless res.code.to_i == 200

    JSON.parse(res.body)
  end

  pid = ENV["INFOMANIAK_PRODUCT_ID"].to_s
  if pid.empty?
    raw = get.call("https://api.infomaniak.com/1/ai")
    products = raw["data"]
    products = [products] if products.is_a?(Hash)
    pid = Array(products).filter_map { |p| p.values_at("id", "product_id", "account_id").compact.first }.first.to_s

    if pid.empty?
      puts "Could not find a product id in GET /1/ai. Raw response:"
      puts JSON.pretty_generate(raw)[0, 1500]
      abort "\nRead the id out of that and: export INFOMANIAK_PRODUCT_ID=<id>"
    end
    puts "product id: #{pid}   (export INFOMANIAK_PRODUCT_ID=#{pid})\n\n"
  end

  # The model list lives on the product-scoped OpenAI route; older accounts expose
  # a global one. Try both before giving up.
  models = nil
  ["https://api.infomaniak.com/2/ai/#{pid}/openai/v1/models",
   "https://api.infomaniak.com/1/ai/models"].each do |url|
    body = begin
      get.call(url)
    rescue SystemExit
      next
    end
    found = body["data"] || body["models"]
    next if found.nil? || Array(found).empty?

    puts "(models from #{url})"
    models = Array(found)
    break
  end
  abort "No model list returned. Check the token has the ai-tools scope." if models.nil?

  puts "models (#{models.size}) — pick a MULTIMODAL one and export INFOMANIAK_MODEL=<id>:"
  models.sort_by { |m| (m["id"] || m["name"]).to_s }.each do |m|
    id = m["id"] || m["name"]
    extra = [m["type"], Array(m["capabilities"]).join(","), m["description"]].compact.reject(&:empty?).join(" | ")
    puts format("  %-34s %s", id, extra[0, 70])
  end
  puts
  puts "Vision-capable candidates on Infomaniak are typically Mistral Small 4 and"
  puts "Gemma-family models. If a model can't see images it will still answer — with"
  puts "nonsense — so confirm the pick against their model page before trusting a run."
  exit
end

# ---------------------------------------------------------------- scoring

def norm(s) = s.to_s.downcase.gsub(/[^a-z0-9]/, "")

def score(image, payload)
  truth = TRUTH[image]
  got   = Array(payload["events"])
  exp   = Array(truth["expect"])

  count_ok = got.size == truth["events"]

  dates_ok = 0
  places_ok = 0
  hallucinated = 0

  exp.each do |e|
    match = got.find { |g| e["date"] && g["date"] == e["date"] } ||
            got.find { |g| e["place"] && norm(g["place"]).include?(norm(e["place"])) }
    next unless match

    dates_ok += 1 if e["date"] == match["date"] || (e["date"].nil? && match["date"].nil?)
    places_ok += 1 if e["place"] && norm(match["place"]).include?(norm(e["place"]))
  end

  # A date invented where ground truth says none is legible is the worst failure.
  exp.each_with_index do |e, i|
    next unless e["date"].nil?

    g = got[i]
    hallucinated += 1 if g && g["date"]
  end

  # Independent of ground truth: a value the model could not quote from the image
  # is self-reported fabrication. Catches invented venues on samples where our
  # ground truth has no opinion.
  uncited = got.count { |g| (g["date"] && !g["date_evidence"]) || (g["place"] && !g["place_evidence"]) }

  { count_ok:, dates_ok:, places_ok:, expected: exp.size, hallucinated:, uncited: }
end

SWISS_CANTONS = %w[AG AI AR BE BL BS FR GE GL GR JU LU NE NW OW SG SH SO SZ TG TI UR VD VS ZG ZH].freeze

# --- Year resolution, in code -------------------------------------------------
#
# Posters almost never print a year. Across 6 runs the model transcribed
# "Mi 19. August" correctly every single time and then resolved it to 2025 in two
# of them — it can read, it just can't reliably do calendar arithmetic. So we do
# the arithmetic here, from the verbatim `date_evidence`.
#
# This is tractable because the candidate set is tiny: a user photographing a
# poster is looking at something happening soon, so the year is last, this, or
# next — and if a weekday is printed it picks exactly one of those (a given
# day/month lands on a given weekday only once every 5-6 years).

WEEKDAY_TOKENS = {
  0 => %w[so son sonntag sunday dimanche dim],
  1 => %w[mo mon montag monday lundi lun],
  2 => %w[di die dienstag tuesday mardi mar],
  3 => %w[mi mit mittwoch wednesday mercredi mer],
  4 => %w[do don donnerstag thursday jeudi jeu],
  5 => %w[fr fre freitag friday vendredi ven],
  6 => %w[sa sam samstag saturday samedi]
}.freeze

MONTH_TOKENS = {
  1 => %w[januar jan janvier], 2 => %w[februar feb fevrier février fev],
  3 => %w[marz märz mar mars], 4 => %w[april apr avril],
  5 => %w[mai may], 6 => %w[juni jun juin],
  7 => %w[juli jul juillet], 8 => %w[august aug aout août],
  9 => %w[september sep sept septembre], 10 => %w[oktober okt oct octobre],
  11 => %w[november nov novembre], 12 => %w[dezember dez dec decembre décembre]
}.freeze

def weekday_in(text)
  t = text.to_s.downcase
  WEEKDAY_TOKENS.each { |wday, toks| return wday if toks.any? { |k| t.match?(/\b#{k}\b/) } }
  nil
end

# Pull day/month/(year) out of the verbatim evidence. Textual months are tried
# first: "Mi 19. August 19.30h" must read as 19 August, not as day 19 month 30.
def day_month_year(text)
  t = text.to_s
  year = t[/\b(20\d{2})\b/, 1]&.to_i

  MONTH_TOKENS.each do |month, toks|
    toks.each do |tok|
      if (m = t.match(/\b(\d{1,2})\s*\.?\s*#{tok}\b/i))
        return [m[1].to_i, month, year]
      end
    end
  end

  if (m = t.match(%r{\b(\d{1,2})\s*[./]\s*(\d{1,2})\b}))
    d, mo = m[1].to_i, m[2].to_i
    return [d, mo, year] if mo.between?(1, 12) && d.between?(1, 31)
  end

  nil
end

# Nearest plausible occurrence, weekday-filtered when a weekday is printed.
# Past is allowed but penalised: a poster for 08.08 seen on 19.08 means the show
# was 11 days ago (stale poster), NOT next year.
def resolve_year(evidence, today = Date.parse(TODAY))
  day, month, year = day_month_year(evidence)
  return nil unless day && month

  return (Date.new(year, month, day) rescue nil) if year

  wday = weekday_in(evidence)
  candidates = [today.year - 1, today.year, today.year + 1].filter_map do |y|
    Date.new(y, month, day)
  rescue Date::Error
    nil
  end
  matching = wday ? candidates.select { |d| d.wday == wday } : candidates
  matching = candidates if matching.empty?

  matching.min_by { |d| (d - today).to_i.negative? ? (today - d).to_i * 3 : (d - today).to_i }
end


def normalize_time(value)
  s = value.to_s.strip
  if (m = s.match(/\A(\d{1,2})[:.](\d{2})/))        then format("%02d:%02d", m[1].to_i, m[2].to_i)
  elsif (m = s.match(/\A(\d{1,2})\s*(?:Uhr|h)\b/i)) then format("%02d:00", m[1].to_i)
  elsif (m = s.match(/\A(\d{1,2})\z/))               then format("%02d:00", m[1].to_i)
  end
end

# Anything deterministic is OUR job, not the model's. Across runs the model
# returned "Mi 19. August" in the `date` field, five different time formats, and
# is_past was wrong every time it tried. So: the model transcribes, this validates.
# A value that fails validation is NULLED (kept under *_raw) rather than trusted —
# a null is completed by a human; a malformed date silently corrupts the feed.
def validate!(payload)
  Array(payload["events"]).each do |e|
    issues = []

    if (d = e["date"])
      # "2026-08-19T19:30:00" is a right answer in a wrong shape — split it,
      # don't bin it. Only genuinely unparseable values get nulled.
      if (m = d.match(/\A(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})/))
        e["date_raw"] = d
        e["date"] = m[1]
        e["time"] ||= m[2]
        issues << "date_was_datetime"
        d = m[1]
      end

      ok = d.match?(/\A\d{4}-\d{2}-\d{2}\z/) && (begin
        Date.strptime(d, "%Y-%m-%d")
      rescue Date::Error
        nil
      end)
      unless ok
        e["date_raw"] = d
        e["date"] = nil
        issues << "date_not_iso"
      end
    end

    if (t = e["time"])
      n = normalize_time(t)
      if n.nil?
        e["time_raw"] = t
        e["time"] = nil
        issues << "time_unparseable"
      elsif n != t
        e["time_raw"] = t
        e["time"] = n
        issues << "time_normalized"
      end
    end

    if (c = e["canton"])
      if SWISS_CANTONS.include?(c.to_s.upcase)
        e["canton"] = c.to_s.upcase
      else
        e["canton_raw"] = c
        e["canton"] = nil
        issues << "canton_invalid"
      end
    end

    # Recompute the year from the evidence and prefer it over the model's guess.
    if (ev = e["date_evidence"]) && e["date"]
      computed = resolve_year(ev)&.to_s
      if computed && computed != e["date"]
        e["date_model"] = e["date"]
        e["date"] = computed
        issues << "year_recomputed"
      end
    end

    e["is_past"] = e["date"] ? (e["date"] < TODAY) : false
    e["issues"]  = issues
  end
  payload
end

# ---------------------------------------------------------------- run

# --prep-only: sanitize everything and STOP. No socket is opened, so this is the
# honest way to inspect what would leave the machine. (Running with a bogus API
# key is NOT equivalent — the request body is uploaded before the 401 comes back.)
if options[:prep_only]
  puts "PREP ONLY — no network calls will be made.\n\n"
  (options[:limit] ? IMAGES.first(options[:limit]) : IMAGES).each do |image|
    _b64, path = prepare(image, options)
    w, h = `sips -g pixelWidth -g pixelHeight "#{path}"`.scan(/\d+$/).map(&:to_i)
    puts format("  %-14s %5dx%-5d %5dKB  ~%d image tokens   %s",
                image, w, h, (File.size(path) / 1024.0).round,
                (w * h / 750.0).round, TRUTH[image]["label"])
  end
  puts "\nWrote #{PREPPED}"
  puts "Opening them now — these exact files are what a real run uploads."
  puts "If anything identifiable survived, fix CHROME_CROP / REDACT_BANDS before running for real."
  system("open", PREPPED)
  exit
end

active = PROVIDERS.select do |name, p|
  next false if options[:only] && options[:only] != name

  p[:ready].call || (warn("skip #{name} — no #{p[:need]}") && false)
end

abort "\nNo provider has credentials. Set at least one key and re-run." if active.empty?

# Output dir carries WHAT was tested, so two sessions can never be confused:
#   tmp/event_capture_bakeoff/20260819-0114-infomaniak-mistral-small-4-119b-2603/
#     run-1/… run-2/… manifest.json
def slug(str)
  str.to_s.downcase.sub(%r{\A[^/]+/}, "").gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
end

stamp   = Time.now.strftime("%Y%m%d-%H%M%S")
tag     = active.keys.map { |n| "#{n}-#{slug(MODEL_IDS[n])}" }.join("_")
SESSION = File.join(OUT, "#{stamp}-#{tag}")
FileUtils.mkdir_p(SESSION)

images = options[:limit] ? IMAGES.first(options[:limit]) : IMAGES
runs   = [options[:runs].to_i, 1].max

File.write(File.join(SESSION, "manifest.json"), JSON.pretty_generate({
  started_at: Time.now.to_s, today: TODAY, runs:, images:,
  models: active.keys.to_h { |n| [n, MODEL_IDS[n]] },
  crop: options[:crop], json_mode: options[:json_mode] != false,
  prompt_sha: Digest::SHA256.hexdigest(SYSTEM)[0, 12]
}))

puts "providers: #{active.keys.map { |n| "#{n} (#{MODEL_IDS[n]})" }.join(', ')}"
puts "runs:      #{runs} x #{images.size} images"
puts "today:     #{TODAY}"
puts "out:       #{SESSION}"
puts "crop:      #{options[:crop] ? 'WhatsApp chrome stripped + phone numbers blacked out' : 'OFF'}"
puts

rows = []

1.upto(runs) do |run|
  run_dir = File.join(SESSION, "run-#{run}")
  FileUtils.mkdir_p(run_dir)
  puts "───────── run #{run}/#{runs}"

  images.each do |image|
    b64, = prepare(image, options)

    active.each do |name, provider|
      t0 = Time.now
      begin
        text, tin, tout, model = provider[:call].call(b64, options)
        payload = validate!(parse_payload(text))
        elapsed = Time.now - t0

        File.write(File.join(run_dir, "#{name}__#{image}.json"),
                   JSON.pretty_generate({ model:, elapsed:, tokens: [tin, tout], payload: }))

        sc = score(image, payload)
        pin, pout = PRICES.fetch(name, [0, 0])
        cost = (tin * pin + tout * pout) / 1_000_000.0
        issues = Array(payload["events"]).sum { |e| Array(e["issues"]).size }

        rows << { provider: name, image:, run:, **sc, cost:, elapsed:, issues:,
                  events: Array(payload["events"]) }

        flag = +""
        flag << " ⚠ #{sc[:hallucinated]} FABRICATED DATE(S)" if sc[:hallucinated].positive?
        flag << " ⚠ #{sc[:uncited]} UNCITED"                 if sc[:uncited].to_i.positive?
        flag << " (#{issues} field fix#{'es' unless issues == 1})" if issues.positive?
        puts format("  %-11s %-14s %d/%d ev  dates %d/%d  places %d/%d  %4.1fs  $%.4f%s",
                    name, image.sub(".PNG", ""), Array(payload["events"]).size,
                    TRUTH[image]["events"], sc[:dates_ok], sc[:expected],
                    sc[:places_ok], sc[:expected], elapsed, cost, flag)
        puts "    parse error: #{payload['_parse_error'][0, 160]}" if payload["_parse_error"]
      rescue StandardError => e
        puts "  #{name.ljust(11)} #{image} ERROR: #{e.message[0, 400]}"
        rows << { provider: name, image:, run:, error: true, cost: 0, elapsed: Time.now - t0 }
      end
    end
  end
  puts
end

# ---------------------------------------------------------------- summary

puts "=" * 78
puts "SUMMARY  (#{runs} run#{'s' unless runs == 1} x #{images.size} images)"
puts "=" * 78
puts format("%-12s %7s %9s %9s %8s %11s %8s %8s",
            "provider", "calls", "counts", "dates", "places", "fabricated", "fixes", "cost")

active.each_key do |name|
  mine = rows.select { |r| r[:provider] == name }
  ok   = mine.reject { |r| r[:error] }
  puts format("%-12s %7d %9s %9s %8s %11d %8d %8s",
              name, mine.size,
              "#{ok.count { |r| r[:count_ok] }}/#{ok.size}",
              "#{ok.sum { |r| r[:dates_ok] }}/#{ok.sum { |r| r[:expected] }}",
              "#{ok.sum { |r| r[:places_ok] }}/#{ok.sum { |r| r[:expected] }}",
              ok.sum { |r| r[:hallucinated] },
              ok.sum { |r| r[:issues].to_i },
              format("$%.4f", mine.sum { |r| r[:cost] }))
end

# ---------------------------------------------------------------- stability

if runs > 1
  puts
  puts "=" * 78
  puts "STABILITY across #{runs} runs — same input, how often does the answer change?"
  puts "=" * 78

  active.each_key do |name|
    puts "\n#{name}:"
    images.each do |image|
      per_run = rows.select { |r| r[:provider] == name && r[:image] == image && !r[:error] }
      next if per_run.empty?

      counts = per_run.map { |r| r[:events].size }.uniq
      puts format("  %-14s event count %s%s", image.sub(".PNG", ""),
                  counts.join("/"), counts.size > 1 ? "   <-- UNSTABLE" : "")

      want = TRUTH[image]["events"]
      (0...want).each do |idx|
        %w[date time place city canton title source_url].each do |field|
          vals = per_run.map { |r| r[:events][idx] && r[:events][idx][field] }
          uniq = vals.map { |v| v.nil? ? "null" : v.to_s }.uniq
          next if uniq.size <= 1

          puts format("    ev%d %-11s %s", idx, field, uniq.join("  |  "))
        end
      end

      # The metric that decides the whole evaluation.
      if Array(TRUTH[image]["expect"]).any? { |e| e["date"].nil? }
        bad = per_run.count { |r| r[:events].any? { |e| e["date"] } }
        puts format("    >> NO DATE EXISTS in this image: fabricated in %d/%d runs (%d%%)",
                    bad, per_run.size, (100.0 * bad / per_run.size).round)
      end
    end
  end
end

puts
puts "Raw responses: #{SESSION}"
puts "Prepped images actually sent: #{PREPPED}"
puts
puts "Read the raw JSON before trusting the table. 'fabricated' (a date where the"
puts "image has none) is the metric that matters; 'fixes' counts values the"
puts "validator had to null or reformat. Monthly cost = per-image cost x 150."
