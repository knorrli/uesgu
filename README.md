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
genre-to-style mappings across 15 styles) is the source of truth and is re-seeded
unchanged. Scrapers that emit clean structured genres may mint new ones; scrapers
parsing free text can only match the dictionary (see `event_consumption_genres`
in `app/services/scrapers/agent.rb`).

To purge junk genre tags that accumulated before that split, rebuild the taxonomy
and re-scrape. This is non-destructive: it keeps events **and user favorites**
(favorites are taggings on the `User` model — `acts_as_taggable_on :locations,
:styles`), so the wipe is scoped to event tags only. Run on prod via the Render
shell.

```sh
# 1. drop EVENT tags only — user favorites (taggable_type "User") are preserved
bin/rails runner "ActsAsTaggableOn::Tagging.where(taggable_type: 'Event').delete_all"

# 2. rebuild the genre/style taxonomy models (the tags table + favorites are untouched)
bin/rails runner "ActiveRecord::Base.connection.execute('TRUNCATE genres, genres_styles, styles RESTART IDENTITY CASCADE')"
bin/rails genres:seed

# 3. re-scrape — re-tags current events; consumption scrapers cannot create junk
bin/rails scrapers:run_all
```

Events still in a venue's listing are re-tagged by the scrape. Events that have
dropped off a listing stay but lose their tags until the next sweep.

Verify the junk is gone and the dictionary is intact:

```sh
bin/rails runner 'puts "events=#{Event.count} genres=#{Genre.count} in_use=#{Genre.in_use.count} unassigned=#{Genre.unassigned.count}"'
```

Notes:

- A plain re-seed or re-scrape will not clean up on its own — `Genre.existing_only`
  keeps matching junk rows that already exist, so the event genre taggings must be
  deleted and the taxonomy rebuilt.
- **Never `TRUNCATE taggings` or `tags`** — that deletes user favorites along with
  event tags.
- `Event#recompute_styles!` is only needed when dispositions or mappings change
  *without* a re-scrape; the scrape already derives each event's styles.
```
