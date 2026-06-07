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
