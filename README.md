# üsgu

**üsgu** ([uesgu.ch](https://uesgu.ch)) — Swiss-German for "Ausgang" (going out).

A concert & event aggregator for Swiss music venues. It scrapes event listings
from live-music venues across Switzerland, normalizes and tags them, and
presents a filterable feed. Users can favorite locations and styles and receive
periodic notifications about newly-added events.

## Stack

- Ruby on Rails 8, PostgreSQL
- Hotwire (Turbo + Stimulus), importmap, Propshaft
- Solid Queue for background jobs (scrapers run daily)
- Mechanize for scraping, acts-as-taggable-on for the location/style/genre taxonomy

## Development

```sh
bin/setup        # install deps, prepare the database
bin/rails server # http://localhost:3000
```

The database is `uesgu_development` (see `config/database.yml`). Event data is
populated by the venue scrapers in `app/services/scrapers/`.

## Maintenance

### Genre vocabulary reset

The genre dictionary (`lib/genres.json` — ~5.7k Spotify / Every-Noise
genre-to-style mappings across 15 styles) is the source of truth and is
re-seeded unchanged. Scrapers that emit clean structured genres may mint new
ones; scrapers parsing free text can only match the dictionary (see
`event_consumption_genres` in `app/services/scrapers/agent.rb`).

To purge junk genre tags that accumulated before that split, wipe and rebuild.
This keeps `users`, `invitations`, and `sessions`; run it on prod via the Render
shell.

```sh
# 1. wipe events + taxonomy (CASCADE clears the joins/FKs)
bin/rails runner 'ActiveRecord::Base.connection.execute("TRUNCATE events, genres, genres_styles, styles, taggings, tags, notifications RESTART IDENTITY CASCADE;")'

# 2. rebuild styles + genre-to-style dictionary + dispositions
bin/rails genres:seed

# 3. re-scrape (consumption scrapers can no longer create junk)
bin/rails scrapers:run_all
```

Verify the junk is gone and the dictionary is intact:

```sh
bin/rails runner 'puts "genres=#{Genre.count} in_use=#{Genre.in_use.count} unassigned=#{Genre.unassigned.count}"'
```

A plain re-seed or re-scrape will not clean up on its own — the junk rows already
exist, so they must be deleted (hence the wipe). `Event#recompute_styles!` is
only needed when dispositions or mappings change *without* a re-scrape; the scrape
already derives each event's styles.
