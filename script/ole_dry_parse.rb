# frozen_string_literal: true

# READ-ONLY dry parse of live OLE feeds — sanity-checks the production
# Scrapers::Ole adapter against real endpoints WITHOUT touching the database.
#
#   bin/rails runner script/ole_dry_parse.rb              # a couple of clean feeds
#   bin/rails runner script/ole_dry_parse.rb Dachstock    # one source by key
#   bin/rails runner script/ole_dry_parse.rb BeJazz       # also reaches DEFERRED
#                                                         # feeds (re-check robots)
#   bin/rails runner script/ole_dry_parse.rb all          # every shipping source
#
# It runs the SAME code the sweep would (fetch → follow pagination → expand
# events×shows → drop past shows → map fields) but stops short of
# find_or_initialize_by/save!, so it writes NOTHING. Use it to confirm a feed
# parses and that every event is upcoming (the date filter actually fired) before
# trusting it in a real sweep.

DEFAULT_KEYS = %w[Klangkeller Dachstock].freeze

# Every configured source by key → its config. SOURCES are the shipping (named +
# registered) classes; DEFERRED ones (e.g. robots-blocked BeJazz) aren't
# registered, so we build a throwaway class on demand to still dry-parse them.
def config_by_key
  (Scrapers::Ole::SOURCES + Scrapers::Ole::DEFERRED).index_by { |s| s[:key] }
end

def source_classes(args)
  keys = args.include?('all') ? Scrapers::Ole::SOURCES.map { |s| s[:key] } : (args.presence || DEFAULT_KEYS)
  configs = config_by_key
  keys.filter_map do |k|
    src = configs[k]
    next warn "  ! unknown source key #{k.inspect} — known: #{configs.keys.join(', ')}" unless src

    if Scrapers.const_defined?("Ole#{k}")
      Scrapers.const_get("Ole#{k}")
    else
      Scrapers::Ole.build(key: src[:key], feed_url: src[:feed_url],
                          place: src[:location], aggregator: src.fetch(:aggregator, false))
    end
  end
end

def dry_parse(klass)
  puts "\n=== #{klass.source_key}  (#{klass.url})"
  scraper = klass.new
  scraper.get(klass.url)              # page 1; #event_rows follows pagination
  rows = scraper.send(:event_rows)    # real parse: paginate + date-filter + expand

  if rows.empty?
    puts '  (no upcoming events)'
    return
  end

  events = rows.map do |row|
    {
      title:    scraper.event_title(row),
      subtitle: scraper.event_subtitle(row),
      start:    scraper.event_start_time(row),
      genres:   scraper.event_consumption_genres(row),
      location: scraper.event_locations(row),
      url:      scraper.event_url(row)
    }
  end.sort_by { |e| e[:start] }

  dates    = events.map { |e| e[:start].to_date }
  mirrors  = events.count { |e| e[:url].to_s.include?('eventfrog') || e[:url].to_s.include?('petzi.ch') }
  past     = dates.count { |d| d < Date.current }

  puts "  #{events.size} upcoming event(s); dates #{dates.min} … #{dates.max}"
  puts "  date filter: #{past.zero? ? 'OK (none before today)' : "FAIL — #{past} past event(s) leaked!"}"
  puts "  url points at venue (no eventfrog/petzi mirror): #{mirrors.zero? ? 'OK' : "FAIL — #{mirrors} mirror url(s)"}"
  puts '  sample:'
  events.first(5).each do |e|
    puts format('    %s  %-34s  %-26s  %s', e[:start].strftime('%Y-%m-%d %H:%M'),
                e[:title].to_s.truncate(34), e[:location].join(' / '), e[:url])
  end
end

classes = source_classes(ARGV)
abort 'no valid sources' if classes.empty?
puts "Dry-parsing #{classes.size} OLE source(s) — READ ONLY, no DB writes."
classes.each do |klass|
  dry_parse(klass)
rescue StandardError => e
  puts "  ! #{e.class}: #{e.message}"
end
puts "\nDone. (Nothing was written.)"
