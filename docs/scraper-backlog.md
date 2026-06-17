# Scraper backlog — venues to add

New venue scrapers. Each lives in `app/services/scrapers/` and declares a clean
`[venue, city, canton]` location (see existing scrapers for the pattern).

## robots.txt policy

We only scrape venues whose `robots.txt` permits it, and **the scraper now
enforces this**: `Scrapers::Agent` sets `self.robots = true` and a custom
`user_agent` (`uesgu/1.0`), so Mechanize obeys robots.txt for every `get`. We
match the generic `User-agent: *` group — üsgu is a personal events reader, not
ClaudeBot/GPTBot, so AI-crawler blocks don't apply to us (confirmed: all venues
below leave `*` open; some Squarespace sites block AI bots only). A disallowed
listing page raises `Mechanize::RobotsDisallowedError` out of `get`, surfacing
the venue as a failed run rather than silently scraping.

**Before adding a venue, check its `robots.txt`** (the `*` group) and record the
verdict so we never recheck. All venues below were checked 2026-06-14: ✅ allowed.

## Done — shipped with golden fixtures

- [x] **Café Kairo** — Bern (BE) — `kairo.rb` — single-page, 18 events. Per-event
      date+time (the server's bad TZ offset is ignored; local wall-clock used).
- [x] **Mühle Hunziken** — Rubigen (BE) — `muehle_hunziken.rb` — list rows (date
      in the URL slug) + detail-page fetch for the "Showbeginn" time. 68 events.
- [x] **Bierhübeli** — Bern (BE) — `bierhuebeli.rb` — WP REST `event` feed
      (`/wp-json/wp/v2/event`); `eventzusatz.datum` timestamp = local show time,
      genre tags from `beschreibungstag`. 100 events. (JSON-API scrape, like
      `rote_fabrik`.)

## Blocked — JS-rendered or no scrapeable date/time

Our scraper stack (Mechanize) does **not execute JavaScript**. These venues need
either their JSON API reverse-engineered (as done for Bierhübeli) or a
headless-browser fetch path we don't have yet. Recorded so we don't re-investigate.

- [ ] **Café Hueber** — Bern (BE) — https://cafehueber.ch/programm/ — *static but
      no times.* Elementor headings `"DD.MM.YYYY - Title"` + an image; no per-event
      time and no detail link, and the programme is mostly non-concert (yoga,
      pizza). Buildable as **date-only** if we accept midnight start times — ask
      before doing so.
- [ ] **Heitere Fahne** — Wabern (BE) — https://www.dieheiterefahne.ch/events —
      *Vue app.* Events live in an `<event-list :initial-data="…">` JSON blob, but
      it carries **no start time** (all `00:00:00`), no per-event URL, and no
      category. Detail URLs ARE deterministic (`/events/{id}/{DD-MM-YYYY}/{slug}`)
      but the detail page is client-side only — **time + category come from a
      `/ajax/` XHR (undocumented backend)**, which we won't call. No JSON-LD, no
      ICS/RSS/sitemap feed. Not in PETZI or OLE. **No clean path to time+genre —
      stays shelved.** Full 2026-06-17 feed/aggregator investigation:
      `docs/open-event-data-research.md`.
- [ ] **Café du Commerce** — Biel/Bienne (BE) — http://www.ducommerce-biel.ch —
      *Squarespace, JS.* No structured events collection (nav is only /menu,
      /search; sitemap has no event pages). The Thursday concert series isn't
      published as machine-readable events.
- [ ] **Café Bar Mokka** — Thun (BE) — https://mokka.ch — *external JS widget.*
      Programme is rendered client-side from `ecomm.events` (Ecwid store
      `43651183`). Would need the ecomm.events API reverse-engineered.
- [ ] **ONO** — Bern (BE) — https://www.onobern.ch — *WP REST lacks the date.* The
      `ajde_events` (EventON) REST endpoint exists but exposes only the post
      publish date, not the event date (stored in unexposed `evcal_*` postmeta).
      Homepage is JS. Would need per-event detail-page parsing.
- [ ] **Marians Jazzroom** — Bern (BE) — https://www.mariansjazzroom.ch/gesamtprogramm —
      *Squarespace, JS.* Events render client-side; static HTML has no dates/times,
      and the page's JSON collection is empty (events are in JS-populated blocks).
- [ ] **PROZESS Kultur & Bar** — Bern (BE) — https://prozess.be — *pure SPA.* The
      page is an empty shell (`<main id="main"></main>`) populated entirely by
      `script.min.js`. Nothing in the static HTML.

## Skipped — promoters / already covered (not venues)

- **bee-flat im PROGR** — the PROGR concert promoter; `Turnhalle` already scrapes
  the bee-flat agenda. A bee-flat scraper would re-cover the same programme.
- **BeJazz** — a roving jazz *series*, not a fixed venue: current events scatter
  across guest venues ("Ausser Haus") and sometimes **Mahogany Hall**, which we
  already scrape. Following "BeJazz" as a location would mislead and duplicate.

## Skipped — robots.txt disallows

_(none yet — record any venue whose `User-agent: *` group blocks its listing
pages here, with the date checked, so we don't re-evaluate it.)_

## Notes

- The bka.ch agenda lists ~213 music "organisations," but most aren't scrapeable
  venues (choirs, orchestras, ensembles, solo artists, management firms, one-off
  festivals, churches). The venues above are the ones with a recurring programme
  not already covered.
