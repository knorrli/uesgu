class DismissStaleSuedpolEvents < ActiveRecord::Migration[8.1]
  # Südpol relaunched (WordPress SPA → server-rendered Contao) and every old
  # /programm/<slug>/ permalink now 404s — the broken links of issue #56. The
  # rewritten scraper keys events on the new ?event=<alias> deep links, and the
  # aliases were RENAMED for a large minority of events (live check: 4 of 10),
  # so rewriting the old keys in place would still strand those — dismiss the
  # stale future rows wholesale instead and let the next sweep rebuild the
  # programme from the new site under the new keys. Dismissed is the soft,
  # sticky remove: rows and bookmarks survive, the feed drops them, and the
  # re-scrape cannot resurrect them (its keys differ anyway). Past rows keep
  # their (dead) links — they are history, not listings.
  def up
    execute(<<~SQL.squish)
      UPDATE events
         SET dismissed_at = NOW()
       WHERE data_source = 'Suedpol'
         AND dismissed_at IS NULL
         AND start_date >= CURRENT_DATE
         AND url LIKE 'https://www.sudpol.ch/programm/%'
    SQL
  end

  # One-shot data fix over rows that no longer exist by the time anyone could
  # roll back — nothing sensible to restore.
  def down; end
end
