namespace :events do
  desc "Remove duplicate events sharing a url, keeping the earliest (lowest id). " \
       "Run once before deploying the unique index on events.url if a legacy " \
       "table might hold duplicates (overlapping scrape runs). Idempotent."
  task dedupe_urls: :environment do
    dupes = Event.group(:url).having("COUNT(*) > 1").count
    removed = 0
    dupes.each_key do |url|
      stale = Event.where(url: url).order(:id).offset(1)
      removed += stale.destroy_all.size
    end
    puts "Removed #{removed} duplicate event(s) across #{dupes.size} url(s)."
  end

  desc "One-off cleanup for the Südpol relaunch (#56): dismiss future Suedpol " \
       "events still keyed on the dead WP-era /programm/<slug>/ permalinks. " \
       "The relaunch renamed a large minority of slugs, so rewriting keys in " \
       "place would strand those — dismiss the stale rows wholesale and let " \
       "the next sweep rebuild the programme under the new ?event= keys. " \
       "Dismissed is the soft, sticky remove: rows and bookmarks survive, the " \
       "feed drops them, and the re-scrape cannot resurrect them (its keys " \
       "differ anyway). Past rows keep their (dead) links — they are history, " \
       "not listings. Idempotent; run once after deploying the rewritten scraper."
  task dismiss_stale_suedpol: :environment do
    count = Event.where(data_source: "Suedpol", dismissed_at: nil)
                 .where(start_date: Date.current..)
                 .where("url LIKE ?", "https://www.sudpol.ch/programm/%")
                 .update_all(dismissed_at: Time.current)
    puts "Dismissed #{count} stale Südpol event(s)."
  end

  desc "One-off cleanup: re-key PETZI events whose url is the venue's homepage onto " \
       "their petzi.ch aggregator_url, which is unique per event. Two events keyed " \
       "on the same homepage would overwrite each other every night. Re-keying in " \
       "place keeps saves and bookmarks; a row whose aggregator_url is already " \
       "taken is skipped and reported. Idempotent."
  task rekey_petzi_homepage_urls: :environment do
    rekeyed = 0
    Event.where(data_source: "Petzi").where.not(aggregator_url: nil).find_each do |event|
      next unless Scrapers::Petzi.homepage?(event.url)

      if Event.exists?(url: event.aggregator_url)
        puts "Skipped #{event.id}: #{event.aggregator_url} is already taken"
        next
      end

      event.update_columns(url: event.aggregator_url)
      rekeyed += 1
    end
    puts "Re-keyed #{rekeyed} PETZI event(s) off a venue homepage."
  end
end
