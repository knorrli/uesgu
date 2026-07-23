namespace :events do
  desc "Remove duplicate events sharing a url, keeping the earliest (lowest id). " \
       "Run once before deploying the unique index on events.url if a legacy " \
       "table might hold duplicates (overlapping scrape runs). Idempotent."
  task dedupe_urls: :environment do
    dupes = Event.group(:url).having("COUNT(*) > 1").count
    removed = 0
    dupes.each_key do |url|
      # Keep the first-seen row; destroy the rest (destroy_all so AATO taggings
      # are cleaned up rather than orphaned).
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
end
