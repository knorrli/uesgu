# üsgu

**üsgu** ([uesgu.ch](https://uesgu.ch)) — Swiss-German for "Ausgang" (going out).

A concert & event aggregator for Swiss music venues. It scrapes event listings
from live-music venues across Switzerland, normalizes and tags them onto a genre
tree, and presents a filterable feed. Users can save filters (and get optional
notifications when new matching events appear) and bookmark individual shows.

## Stack

- Ruby on Rails 8, PostgreSQL
- Hotwire (Turbo + Stimulus), importmap, Propshaft
- Scrapers run daily via a Render cron task (`scrapers:run_all`, `perform_now`)
- Mechanize for scraping, acts-as-taggable-on for the location/genre taxonomy

## Development

```sh
bin/setup        # install deps, prepare the database
bin/rails server # http://localhost:3000
```

The database is `uesgu_development` (see `config/database.yml`). Event data is
populated by the venue scrapers in `app/services/scrapers/`.

## Maintenance

### Genre vocabulary reset

The curated genre **tree** lives in `db/genres.yml` (~18 roots / ~227 nested
genres) and is the source of truth, loaded idempotently by
`bin/rails taxonomy:import_tree`. Scrapers that emit clean structured genres may
mint new ones — they arrive **unplaced** in the admin curation queue; scrapers
parsing free text can only match existing genres (see `event_consumption_genres`
in `app/services/scrapers/agent.rb`).

To rebuild the taxonomy from the seed (after cultivating `db/genres.yml`, or to
purge accumulated junk), run the reset task, then re-scrape. Run on prod via the
Render shell:

```sh
# 1. wipe + reload the genre tree from db/genres.yml, then recompute every
#    event's `hidden` flag from genre dispositions (idempotent)
bin/rails taxonomy:reset

# 2. re-scrape — re-tags current events; consumption scrapers cannot create junk
bin/rails scrapers:run_all
```

`taxonomy:reset` deletes the `genres` rows, re-imports the tree, and runs
`Event.find_each(&:recompute_visibility!)`. Events keep their raw `genres`
taggings; events still in a venue's listing are re-tagged by the scrape, ones
that dropped off keep their tags until the next sweep.

Verify:

```sh
bin/rails runner 'puts "events=#{Event.count} genres=#{Genre.count} placed=#{Genre.placed.count} unplaced=#{Genre.unplaced.count}"'
```

Notes:

- The `Style` layer and the user **Favorites** feature were removed in the
  taxonomy + saved-filters refactor (2026-06-20) — there are no `styles` /
  `genres_styles` tables and no user taggings to protect anymore, so the reset is
  free to delete and rebuild `genres` outright.
- `Event#recompute_visibility!` (renamed from `recompute_styles!`) is only needed
  when dispositions change *without* a re-scrape; `taxonomy:reset` and each scrape
  already run it.
