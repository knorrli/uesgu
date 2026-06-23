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
end
