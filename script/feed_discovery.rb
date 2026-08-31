# frozen_string_literal: true

require 'mechanize'
require 'json'
require 'yaml'
require 'date'

UA       = 'uesgu-discovery/1.0 (+https://uesgu.ch; event-feed reconnaissance)'
LEDGER   = File.expand_path('../config/venue_ledger.yml', __dir__)
THROTTLE = 0.4

ICS_PATHS = ['/events/?ical=1', '/?ical=1', '/event/?ical=1',
             '/agenda/?ical=1', '/?post_type=tribe_events&tribe-bar-date=&ical=1'].freeze
RSS_PATHS = ['/feed/', '/events/feed/', '/agenda/feed/', '/?feed=rss2', '/blog/feed/'].freeze
SITEMAPS  = ['/sitemap.xml', '/sitemap_index.xml', '/wp-sitemap.xml'].freeze

WP_EVENT_PLUGINS = {
  'tribe_events' => ['The Events Calendar', '/wp-json/tribe/events/v1/events?per_page=3', :rest],
  'mec-events'   => ['Modern Events Calendar', nil, :ajax],
  'mep_events'   => ['WP Event Manager', nil, :ajax],
  'ajde_events'  => ['EventON', nil, :ajax],
  'event'        => ['generic "event" CPT', '/wp-json/wp/v2/event?per_page=3', :rest],
  'events'       => ['generic "events" CPT', '/wp-json/wp/v2/events?per_page=3', :rest]
}.freeze

EVENT_LINK_RX = %r{/(agenda|programm?|events?|konzerte?|veranstaltung|termine?|daten|spielplan|gigs?|shows?)\b}i

AI_BOTS = %w[ClaudeBot GPTBot CCBot Google-Extended anthropic-ai PerplexityBot Applebot-Extended Bytespider].freeze

Fetched = Struct.new(:url, :code, :type, :body, :error, keyword_init: true) do
  def ok?             = code == 200 && error.nil?
  def robots_blocked? = error == :robots
end

def agent
  @agent ||= Mechanize.new do |a|
    a.user_agent  = UA
    a.robots      = true
    a.open_timeout = 12
    a.read_timeout = 18
    a.redirect_ok  = true
    a.max_history  = 0
  end
end

def fetch(url)
  sleep THROTTLE
  p = agent.get(url)
  Fetched.new(url: url, code: p.code.to_i, type: p.respond_to?(:header) ? p.header['content-type'].to_s : '', body: p.body)
rescue Mechanize::RobotsDisallowedError
  Fetched.new(url: url, error: :robots)
rescue Mechanize::ResponseCodeError => e
  Fetched.new(url: url, code: e.response_code.to_i, error: :http)
rescue StandardError => e
  Fetched.new(url: url, error: e.class.to_s.sub(/\AMechanize::/, ''))
end

def squish(str) = str.to_s.gsub(/\s+/, ' ').strip
def future_ymd?(ymd) = ymd && ymd >= Date.today.strftime('%Y%m%d')

def classify_ics(f)
  return nil unless f.ok? && f.body =~ /\ABEGIN:VCALENDAR/i

  vevents = f.body.scan(/^BEGIN:VEVENT/i).size
  starts  = f.body.scan(/^DTSTART[^:]*:(\d{8})/i).flatten
  future  = starts.any? { |d| future_ymd?(d) }
  "#{vevents} VEVENT#{'s' if vevents != 1}#{future ? ', future dates' : ', no future dates'}"
end

def classify_rss(f)
  return nil unless (f.ok? && f.type =~ /xml|rss|atom/i) || (f.ok? && f.body =~ /<(rss|feed)\b/)

  doc = Nokogiri::XML(f.body)
  doc.remove_namespaces!
  items = doc.css('item')
  items = doc.css('entry') if items.empty?
  return nil if items.empty?

  dated = items.css('pubDate, published, updated').any?
  "#{items.size} item#{'s' if items.size != 1}#{dated ? ', dated' : ''}"
end

def classify_tribe(f)
  return nil unless f.ok? && f.type =~ /json/i

  data = JSON.parse(f.body) rescue (return nil)
  return nil unless data.is_a?(Hash)

  events = data['events']
  return nil unless events.is_a?(Array) && events.any?

  sample = events.first
  start  = sample['start_date'] || sample['utc_start_date']
  "#{data['total'] || events.size} events, e.g. #{squish(sample['title'])[0, 40]} @ #{start}"
end

def each_jsonld(data, &blk)
  case data
  when Array then data.each { |d| each_jsonld(d, &blk) }
  when Hash  then blk.call(data); each_jsonld(data['@graph'], &blk) if data['@graph']
  end
end

def jsonld_events(body)
  doc = Nokogiri::HTML(body)
  events = []
  doc.css('script[type="application/ld+json"]').each do |node|
    parsed = JSON.parse(node.text) rescue next
    each_jsonld(parsed) do |obj|
      next unless Array(obj['@type']).any? { |t| t.to_s =~ /Event\z/ }

      events << { title: squish(obj['name'])[0, 40], start: obj['startDate'] }
    end
  end
  events
end

def autodiscovery(body)
  doc  = Nokogiri::HTML(body)
  out  = { rss: [], ics: [], json: [] }
  doc.css('link[rel="alternate"], link[rel="feed"]').each do |l|
    type = l['type'].to_s
    href = l['href'].to_s
    next if href.empty?

    out[:rss]  << href if type =~ %r{application/(rss|atom)\+xml}
    out[:ics]  << href if type =~ %r{text/calendar} || href =~ /\.ics(\?|$)|ical=1/
    out[:json] << href if type =~ %r{application/(ld\+)?json}
  end
  doc.css('a[href$=".ics"], a[href*="ical=1"], a[href^="webcal:"]').each { |a| out[:ics] << a['href'] }
  out.transform_values { |v| v.map { |h| squish(h) }.uniq.first(4) }
end

def detect_cms(body, headers)
  gen = Nokogiri::HTML(body).at_css('meta[name="generator"]')&.[]('content').to_s
  return 'WordPress'    if gen =~ /WordPress/i || body =~ %r{/wp-(content|json|includes)/}
  return 'Squarespace'  if gen =~ /Squarespace/i || body =~ /static1\.squarespace\.com/
  return 'Wix'          if headers['x-wix-request-id'] || body =~ /static\.wixstatic\.com/
  return 'Ecwid widget' if body =~ /ecwid/i

  gen.empty? ? nil : squish(gen)[0, 30]
end

def analyze_robots(base)
  f = fetch("#{base}/robots.txt")
  return { ok: false } unless f.ok?

  sitemaps = f.body.scan(/^\s*Sitemap:\s*(\S+)/i).flatten
  ai_block = nil
  current  = []
  after_rule = false
  f.body.each_line do |line|
    if line =~ /^\s*User-agent:\s*(.+?)\s*$/i
      current = [] if after_rule
      current << Regexp.last_match(1)
      after_rule = false
    elsif line =~ %r{^\s*Disallow:\s*/\s*$}i
      after_rule = true
      hit = current & AI_BOTS
      ai_block ||= hit.first if hit.any?
    elsif line =~ /^\s*(Allow|Disallow|Crawl-delay):/i
      after_rule = true
    end
  end
  { ok: true, sitemaps: sitemaps.uniq, ai_block: ai_block }
end

def first_sitemap(base, rob)
  urls = rob[:sitemaps].to_a.empty? ? SITEMAPS.map { |p| base + p } : rob[:sitemaps]
  urls.first(3).each do |sm|
    f = fetch(sm)
    next unless f.ok? && f.body =~ /<(urlset|sitemapindex)\b/

    locs = Nokogiri::XML(f.body).tap(&:remove_namespaces!).css('loc').map(&:text)
    if f.body =~ /<sitemapindex/ && locs.any?
      sub = fetch(locs.first)
      locs = Nokogiri::XML(sub.body).tap(&:remove_namespaces!).css('loc').map(&:text) if sub.ok?
    end
    return [sm, locs] if locs.any?
  end
  [nil, []]
end

def event_detail_urls(locs)
  locs.select do |u|
    next false unless u =~ EVENT_LINK_RX
    next false if u =~ /\.(jpg|jpeg|png|gif|webp|pdf)\z/i

    u.sub(%r{\Ahttps?://[^/]+}, '').count('/') >= 2
  end
end

def recon(domain, label)
  base = "https://#{domain}"
  hits = []
  add  = ->(tier, text) { hits << [tier, text] if text }

  rob = analyze_robots(base)
  robits = if !rob[:ok]
             'no robots.txt'
  else
             bits = []
             bits << "sitemap×#{rob[:sitemaps].size}" if rob[:sitemaps].any?
             bits << (rob[:ai_block] ? "AI-OPT-OUT (#{rob[:ai_block]})" : 'AI-open')
             bits.join(', ')
  end

  sm_url, sm_locs = first_sitemap(base, rob)

  home  = fetch(base)
  pages = [home].compact
  cms   = nil
  events_url = nil
  if home.ok?
    cms  = detect_cms(home.body, {})
    link = Nokogiri::HTML(home.body).css('a[href]').map { |a| a['href'] }
                   .find { |h| h =~ EVENT_LINK_RX && h !~ /\.(jpg|png|pdf)/i }
    if link
      events_url = link.start_with?('http') ? link : "#{base}#{link.start_with?('/') ? '' : '/'}#{link}"
      ev = fetch(events_url)
      pages << ev if ev&.ok?
    end
  end

  disco = { rss: [], ics: [], json: [] }
  ld    = []
  pages.each do |pg|
    next unless pg.ok? && pg.type =~ /html/i

    ld.concat(jsonld_events(pg.body))
    a = autodiscovery(pg.body)
    %i[rss ics json].each { |k| disco[k] |= a[k] }
  end
  unless ld.empty?
    dated  = ld.select { |e| e[:start] }
    sample = dated.first || ld.first
    add.call(dated.any? ? :time : :weak,
             "json-ld: #{ld.size} Event#{'s' if ld.size != 1} on listing#{dated.any? ? ", e.g. \"#{sample[:title]}\" @ #{sample[:start]}" : ' (no startDate)'}")
  end
  add.call(:weak, "autodiscovery → RSS #{disco[:rss].first}") if disco[:rss].any?
  add.call(:time, "autodiscovery → iCal #{disco[:ics].first}") if disco[:ics].any?

  ical_urls = (disco[:ics].map { |h| h.start_with?('http') ? h : "#{base}#{h}" } +
               ICS_PATHS.map { |p| base + p }).uniq.first(6)
  ical_urls.each do |u|
    desc = classify_ics(fetch(u))
    next unless desc

    add.call(:time, "iCal #{u}  (#{desc})")
    break
  end

  if cms == 'WordPress' || home.body.to_s =~ %r{/wp-json}
    types = fetch("#{base}/wp-json/wp/v2/types")
    if types.ok? && (j = (JSON.parse(types.body) rescue nil))
      (j.keys & WP_EVENT_PLUGINS.keys).each do |slug|
        name, route, kind = WP_EVENT_PLUGINS[slug]
        if slug == 'tribe_events'
          d = classify_tribe(fetch(base + route))
          add.call(d ? :time : :weak, "wp-rest: #{name} → #{d || 'route present'}")
        elsif kind == :rest && route
          r = fetch(base + route)
          live = r.ok? && ((JSON.parse(r.body) rescue nil).is_a?(Array))
          add.call(:weak, "wp-rest: #{name} → #{live ? 'collection live (post dates — verify event date)' : 'route present'}")
        else
          add.call(:weak, "wp: #{name} detected (#{kind} — no clean public REST)")
        end
      end
    end
  end

  unless hits.any? { |t, _| t == :time }
    event_detail_urls(sm_locs).first(3).each do |u|
      pg = fetch(u)
      next unless pg.ok? && pg.type =~ /html/i

      ev = jsonld_events(pg.body).find { |e| e[:start] }
      next unless ev

      add.call(:time, "detail json-ld: #{u}  (Event \"#{ev[:title]}\" startDate #{ev[:start]})")
      break
    end
  end

  add.call(:weak, 'squarespace: ?format=json/ical feed exists but robots-disallowed by default (opt-out option)') if cms == 'Squarespace'

  if disco[:rss].empty?
    RSS_PATHS.each do |p|
      desc = classify_rss(fetch(base + p))
      next unless desc

      add.call(:weak, "rss #{base + p}  (#{desc})")
      break
    end
  end

  if sm_locs.any?
    evs = sm_locs.count { |u| u =~ EVENT_LINK_RX }
    add.call(:weak, "sitemap #{sm_url}  (#{sm_locs.size} URLs, ~#{evs} event-ish)")
  end

  print_report(domain, label, robits, cms, home, hits)
end

def print_report(domain, label, robits, cms, home, hits)
  star = hits.any? { |t, _| t == :time } ? '★' : (hits.any? ? '✓' : '·')
  puts "#{star} #{domain}  [#{label}]"
  puts "    robots : #{robits}"
  puts "    site   : #{cms || (home.ok? ? 'server-rendered HTML' : "unreachable (#{home.error || home.code})")}"
  if hits.empty?
    puts '    signals: none found'
  else
    hits.sort_by { |t, _| t == :time ? 0 : 1 }.each { |t, text| puts "    #{t == :time ? '★' : '✓'} #{text}" }
  end
  verdict = if hits.any? { |t, _| t == :time } then 'TIME-BEARING FEED — buildable ★'
  elsif hits.any?                     then 'weak signal only (no clean time source)'
  else                                     'nothing machine-readable found'
  end
  puts "    VERDICT: #{verdict}"
  puts
end

def ledger_rows
  YAML.load_file(LEDGER, permitted_classes: [Date])['venues']
end

argv = ARGV.dup
mode = argv.delete('--js')

targets =
  if argv.any?
    argv.map { |d| [d.sub(%r{\Ahttps?://}, '').sub(%r{/.*}, ''), 'adhoc'] }
  elsif mode
    ledger_rows.select { |r| %w[js_only no_date].include?(r['reason']) }
               .map { |r| [r['domain'], "#{r['disposition']}/#{r['reason']}"] }
  else
    ledger_rows.map { |r| [r['domain'], r['reason'] ? "#{r['disposition']}/#{r['reason']}" : r['disposition']] }
  end

puts "Feed discovery — #{targets.size} domain(s). UA: #{UA}"
puts "Legend: ★ time-bearing structured feed  ·  ✓ weak signal  ·  · nothing\n\n"

targets.each do |domain, label|
  recon(domain, label)
rescue StandardError => e
  puts "· #{domain}  [#{label}]\n    ERROR: #{e.class}: #{e.message} (#{e.backtrace.first})\n\n"
end

puts 'Done. (Reconnaissance only — nothing persisted. Record decisions in config/venue_ledger.yml.)'
