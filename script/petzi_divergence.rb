# frozen_string_literal: true

# DIVERGENCE HARNESS — run with: bin/rails runner script/petzi_divergence.rb
# Read-only: runs each bespoke scraper LIVE in capture mode (no DB writes) and
# the PETZI extraction for the same venue, then diffs them to quantify how much
# reconciliation a keep-both merge would cost. Writes docs/petzi-divergence-report.md.

require 'minitest/mock' # gives Object#stub in a plain runner

# 14 venues present in BOTH PETZI and our bespoke scrapers (anchored-slug verified).
# Le Singe / Zent are NOT in PETZI (earlier counts were substring false positives).
VENUES = [
  { slug: 'dachstock',     petzi: 'dachstock' },
  { slug: 'isc',           petzi: 'isc' },
  { slug: 'kairo',         petzi: 'cafe-kairo' },
  { slug: 'gaskessel',     petzi: 'gaskessel' },
  { slug: 'kofmehl',       petzi: 'kulturfabrik-kofmehl' },
  { slug: 'fri_son',       petzi: 'fri-son' },
  { slug: 'sedel',         petzi: 'sedel' },
  { slug: 'nouveau_monde', petzi: 'nouveau-monde' },
  { slug: 'helsinki',      petzi: 'helsinki' },
  { slug: 'docks',         petzi: 'docks' },
  { slug: 'treibhaus',     petzi: 'treibhaus' },
  { slug: 'neubad',        petzi: 'neubad' },
  { slug: 'kiff',          petzi: 'kiff' },
  { slug: 'boeroem',       petzi: 'borom' }
].freeze

PETZI_SITEMAP = 'https://www.petzi.ch/en/sitemap.xml'
PER_VENUE_TIMEOUT = 600 # seconds; one slow venue can't block the rest

# --- Event capture stand-in (mirrors golden_test's Capture, but tolerant) -----
class Capture
  attr_accessor :start_time, :start_date, :title, :subtitle, :genre_list,
                :style_list, :location_list, :cancelled_at, :hidden,
                :discarded_by_rule_id
  attr_reader :url

  def initialize(url) = @url = url
  def new_record? = true
  def id = nil
  def dismissed? = false
  def overridden?(_ = nil) = false
  def hidden_by_genre? = false
  def changed? = false
  def save! = nil
  # absorb any field setter process_events might call that we didn't anticipate
  def method_missing(name, *) = name.to_s.end_with?('=') ? nil : nil
  def respond_to_missing?(*) = true
end

BY_SLUG = Scrapers::All.scrapers.transform_keys(&:underscore)

# Run a bespoke scraper live, capturing built events without touching the DB.
def capture_bespoke(klass)
  events = []
  factory = ->(*, **kw) { Capture.new(kw[:url]).tap { |c| events << c } }
  Event.stub(:find_or_initialize_by, factory) do
    Genre.stub(:existing_only, ->(names) { Array(names) }) do # echo: compare proposed genres
      scraper = klass.new
      scraper.define_singleton_method(:event_styles) { |genres:| Array(genres) }
      scraper.send(:process_events)
    end
  end
  events.filter_map do |e|
    next unless e.start_date
    { date: e.start_date.to_s, title: e.title.to_s,
      time: (e.start_time.strftime('%H:%M') if e.start_time),
      genres: Array(e.genre_list) }
  end
end

# --- PETZI extraction (folds in the POC logic) --------------------------------
def petzi_agent
  @petzi_agent ||= Mechanize.new do |a|
    a.user_agent = 'uesgu/1.0'
    a.robots = true
    a.open_timeout = 15
    a.read_timeout = 20
  end
end

def sq(s) = s.to_s.gsub(/\s+/, ' ').strip

def petzi_event_urls
  @petzi_urls ||= begin
    xml = Nokogiri::XML(petzi_agent.get(PETZI_SITEMAP).body)
    xml.remove_namespaces!
    xml.css('loc').map(&:text).grep(%r{/events/})
  end
end

def petzi_extract(page)
  doc = page.parser
  bar = sq(doc.at_css('title')&.text).split(' / ')
  body = sq(doc.text)
  { date: petzi_date(bar.find { |p| p =~ /\A\d{2}\.\d{2}\.\d{4}\z/ }),
    title: sq(doc.at_css('h1')&.text),
    doors: body[/Doors open at:\s*(\d{1,2}[:.]\d{2})/i, 1],
    show: body[/Event starts at:\s*(\d{1,2}[:.]\d{2})/i, 1],
    genres: doc.css('a.tag').map { |a| sq(a.text) }.reject(&:empty?).uniq }
end

def petzi_date(ddmmyyyy)
  return nil unless ddmmyyyy
  d, m, y = ddmmyyyy.split('.')
  "#{y}-#{m}-#{d}"
end

def capture_petzi(petzi_slug)
  urls = petzi_event_urls.select { |u| u =~ %r{/events/\d+-#{Regexp.escape(petzi_slug)}-} }
  urls.filter_map do |u|
    ev = petzi_extract(petzi_agent.get(u))
    sleep 0.4 # politeness between detail fetches
    next unless ev[:date]
    ev.merge(url: u)
  rescue StandardError
    nil
  end
end

# --- Matching -----------------------------------------------------------------
STOP = %w[the a le la les der die das und and feat featuring with vs b2b support
          live concert show tour ch us uk fr de present presents].freeze

def tokens(title)
  title.to_s.downcase
       .tr('äöüàâéèêëïîçáí', 'aouaaeeeeiicai')
       .gsub(/\(.*?\)/, ' ')
       .gsub(/[^a-z0-9 ]/, ' ')
       .split
       .reject { |t| STOP.include?(t) || t.length < 2 }
       .to_set
end

def jaccard(a, b)
  return 0.0 if a.empty? || b.empty?
  (a & b).size.to_f / (a | b).size
end

# Best fuzzy match for a petzi event among scraper events on the same date.
# Returns [scraper_ev, score, matched?]. Truncated titles (our club scrapers keep
# only the series name, e.g. "Darkside", while PETZI lists the full DJ lineup) are
# caught by a token-subset rule, not just Jaccard.
def best_match(petzi_ev, scraper_evs)
  pt = tokens(petzi_ev[:title])
  cands = scraper_evs.select { |s| s[:date] == petzi_ev[:date] }
  return nil if cands.empty?
  scored = cands.map do |s|
    st = tokens(s[:title])
    subset = !st.empty? && (st.subset?(pt) || pt.subset?(st))
    [s, jaccard(pt, st), subset]
  end
  best = scored.max_by { |_, j, sub| [sub ? 1 : 0, j] }
  s, j, sub = best
  [s, j, (j >= 0.4 || sub)]
end

# --- Run ----------------------------------------------------------------------
report = +"# PETZI vs bespoke scraper — divergence report\n\n"
report << "Generated by `script/petzi_divergence.rb` (live, read-only). PETZI is the\n"
report << "candidate primary; we measure how much a keep-both merge must reconcile.\n\n"
summary = []

venues = ENV['ONLY'] ? VENUES.select { |v| ENV['ONLY'].split(',').include?(v[:slug]) } : VENUES
venues.each do |v|
  klass = BY_SLUG[v[:slug]]
  line = { venue: v[:slug] }
  print "#{v[:slug]}… "
  begin
    Timeout.timeout(PER_VENUE_TIMEOUT) do
      bespoke = capture_bespoke(klass)
      petzi   = capture_petzi(v[:petzi])

      # Compare only within the date window both sources cover, so a different
      # horizon (or PETZI's natural listing depth) isn't miscounted as a "miss".
      dates = (bespoke.map { _1[:date] } + petzi.map { _1[:date] }).compact
      if dates.empty?
        line.merge!(bespoke: bespoke.size, petzi: petzi.size, note: 'no dated events')
        report << "## #{v[:slug]} — no dated events to compare\n\n"
        summary << line
        puts 'no dates'
        next
      end
      lo = [bespoke.map { _1[:date] }.min, petzi.map { _1[:date] }.min].compact.max
      hi = [bespoke.map { _1[:date] }.max, petzi.map { _1[:date] }.max].compact.min
      in_window = ->(e) { e[:date] && e[:date] >= lo && e[:date] <= hi }
      bw = bespoke.select(&in_window)
      pw = petzi.select(&in_window)

      matched = []
      petzi_only = []
      used = []
      pw.each do |pe|
        m = best_match(pe, bw)
        if m && m[2] && !used.include?(m[0].object_id)
          used << m[0].object_id
          matched << { petzi: pe, scraper: m[0], score: m[1] }
        else
          petzi_only << pe
        end
      end
      scraper_only = bw.reject { |s| used.include?(s.object_id) }

      # A "real" time divergence is when the scraper's time matches NEITHER petzi's
      # show NOR its doors (doors-vs-show is just a semantic offset, fully reconcilable).
      norm = ->(t) { t&.tr('.', ':') }
      timed = matched.select { |m| m[:scraper][:time] && (m[:petzi][:show] || m[:petzi][:doors]) }
      time_diffs   = timed.select { |m| ![norm.(m[:petzi][:show]), norm.(m[:petzi][:doors])].include?(m[:scraper][:time]) }
      doors_used   = timed.count { |m| m[:scraper][:time] == norm.(m[:petzi][:doors]) && m[:scraper][:time] != norm.(m[:petzi][:show]) }
      gdown = ->(g) { g.map(&:downcase).to_set }
      genre_diffs    = matched.select { |m| gdown.(m[:petzi][:genres]) != gdown.(m[:scraper][:genres]) }
      genre_p_adds   = matched.count { |m| m[:scraper][:genres].empty? && m[:petzi][:genres].any? }     # petzi fills a gap
      genre_s_adds   = matched.count { |m| m[:petzi][:genres].empty? && m[:scraper][:genres].any? }      # scraper fills a gap
      genre_conflict = matched.count { |m| m[:petzi][:genres].any? && m[:scraper][:genres].any? && gdown.(m[:petzi][:genres]) != gdown.(m[:scraper][:genres]) }

      line.merge!(window: "#{lo}..#{hi}", bespoke: bespoke.size, petzi: petzi.size,
                  bw: bw.size, pw: pw.size, matched: matched.size,
                  petzi_only: petzi_only.size, scraper_only: scraper_only.size,
                  time_diff: time_diffs.size, doors_used: doors_used,
                  g_petzi_adds: genre_p_adds, g_scraper_adds: genre_s_adds, g_conflict: genre_conflict)
      summary << line

      # Detailed section
      report << "## #{v[:slug]}  (#{klass})\n\n"
      report << "- window compared: **#{lo} → #{hi}**\n"
      report << "- totals: bespoke=#{bespoke.size}, petzi=#{petzi.size} | in-window: bespoke=#{bw.size}, petzi=#{pw.size}\n"
      report << "- **matched=#{matched.size}**, petzi-only=#{petzi_only.size}, scraper-only=#{scraper_only.size}\n"
      report << "- on matched events: **real time conflicts=#{time_diffs.size}** (scraper matches neither petzi show nor doors); scraper-uses-doors=#{doors_used} (reconcilable offset)\n"
      report << "- genres on matched: petzi-fills-gap=#{genre_p_adds}, scraper-fills-gap=#{genre_s_adds}, both-present-but-differ=#{genre_conflict} (mostly granularity, not conflict)\n\n"
      unless time_diffs.empty?
        report << "  ⚠️ time differences (petzi show vs scraper):\n"
        time_diffs.first(8).each { |m| report << "  - #{m[:scraper][:date]} “#{m[:scraper][:title]}” petzi=#{m[:petzi][:show]} (doors #{m[:petzi][:doors] || '—'}) scraper=#{m[:scraper][:time]}\n" }
        report << "\n"
      end
      unless petzi_only.empty?
        report << "  🟦 petzi-only (scraper missed, in window):\n"
        petzi_only.first(8).each { |e| report << "  - #{e[:date]} “#{e[:title]}”\n" }
        report << "\n"
      end
      unless scraper_only.empty?
        report << "  🟧 scraper-only (petzi missed, in window):\n"
        scraper_only.first(8).each { |e| report << "  - #{e[:date]} “#{e[:title]}”\n" }
        report << "\n"
      end
      unless genre_diffs.empty?
        report << "  🎵 genre differences (sample):\n"
        genre_diffs.first(6).each { |m| report << "  - “#{m[:scraper][:title]}” petzi=#{m[:petzi][:genres].inspect} scraper=#{m[:scraper][:genres].inspect}\n" }
        report << "\n"
      end
      puts "ok (m=#{matched.size} po=#{petzi_only.size} so=#{scraper_only.size} t≠=#{time_diffs.size})"
    end
  rescue StandardError, Timeout::Error => e
    line.merge!(error: "#{e.class}: #{e.message}")
    summary << line
    report << "## #{v[:slug]} — ERROR: #{e.class}: #{e.message}\n\n"
    puts "ERROR #{e.class}"
  end
end

# --- Aggregate table ----------------------------------------------------------
report << "\n## Summary\n\n"
report << "| venue | window | bespoke | petzi | matched | petzi-only | scraper-only | real-time≠ | doors-used | g:petzi-adds | g:scraper-adds | g:conflict |\n"
report << "|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|\n"
summary.each do |l|
  if l[:error]
    report << "| #{l[:venue]} | ERROR | | | | | | | | | | |\n"
  else
    report << "| #{l[:venue]} | #{l[:window]} | #{l[:bespoke]} | #{l[:petzi]} | #{l[:matched]} | #{l[:petzi_only]} | #{l[:scraper_only]} | #{l[:time_diff]} | #{l[:doors_used]} | #{l[:g_petzi_adds]} | #{l[:g_scraper_adds]} | #{l[:g_conflict]} |\n"
  end
end

path = Rails.root.join('docs/petzi-divergence-report.md')
File.write(path, report)
puts "\nWrote #{path}"
puts "\n=== SUMMARY ==="
summary.each { |l| puts l.inspect }
