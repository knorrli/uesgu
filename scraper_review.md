# Scraper review — overnight auto-run

**Branch:** `auto-scrapers` (committed, **not** pushed)
**What this is:** 14 new venue scrapers, drafted + **dry-run live** (real HTTP, **zero DB writes**, no genres minted). Below is what each one actually parsed off the live sites tonight so you can eyeball date/title correctness before anything goes live. Sample output for every venue is in `tmp/dry_run/<venue>.json`.

> **How "wiring up" works here — please read.** Scrapers self-register via `Registerable#inherited`, so simply *existing* in `app/services/scrapers/` enrolls them in the nightly sweep (`scrapers:run_all`). Nothing runs while this branch is unmerged. **Merging `auto-scrapers` → `main` is the wiring step** — at that point every venue below goes live in the daily Render cron. To activate only a subset, delete the scrapers you don't want before merging. I did **not** run any scraper against the database.

## Decisions I need from you (everything else is just "looks good?")

1. **Turnhalle is ambiguous** — there's no Turnhalle site. Its concerts are booked by **bee-flat** (music-only, what I scraped) but the **PROGR house agenda** lists all Turnhalle events incl. football screenings & theatre. I went with bee-flat. OK, or do you want the PROGR agenda instead? (details below)
2. **Genre minting:** all new JSON venues with clean genre fields (Le Singe, Bar 59, Südpol, Rote Fabrik, Dynamo) are wired as **consumption** (match-only — they can't add new genres to your curated vocabulary). If you'd rather a clean source *seed* taxonomy, say which and I'll flip it to discovery (one-line change). My default follows your taxonomy-hygiene "new sources → consumption" rule.
3. **Südpol location** is declared `['Südpol', 'Luzern', 'LU']` though it's physically in Kriens. Keep "Luzern" (matches your grouping) or change to "Kriens"?
4. **Mascotte (Zürich) deferred** — it's a two-step JSONP feed that's empty right now (summer break till 06.08). I can build it but couldn't validate it tonight. Want it?

---

## Summary

| Venue | City | Source | rows→parsed | Status |
|---|---|---|---|---|
| Dampfzentrale | Bern | HTML (homepage) | 23→23 | ✅ |
| Sous Soul | Bern | HTML + detail | 34→34 | ✅ |
| Zent | Bern | HTML | 0→0 | ✅ empty now¹ |
| Turnhalle | Bern | HTML (bee-flat) | 5→5 | ⚠️ source choice |
| Le Singe | Biel | **JSON** | 40→40 | ✅ |
| Treibhaus | Luzern | HTML | 22→22 | ⚠️ no concert filter |
| Neubad | Luzern | HTML + detail | 60→11 | ✅ (music-filtered) |
| Bar 59 | Luzern | **JSON** (Firestore) | 37→37 | ⚠️ placeholders |
| Südpol | Luzern | **JSON** (WP API) | 16→16 | ✅ (music-filtered) |
| Kaserne | Basel | HTML | 5→5 | ✅ |
| Volkshaus | Basel | HTML | 20→6 | ⚠️ comedy in "musik" |
| Rote Fabrik | Zürich | **JSON** | 13→13 | ✅ (music-filtered) |
| Dynamo | Zürich | **JSON** (Drupal) | 50→44 | ✅ (music-filtered) |
| Helsinki Klub | Zürich | HTML | 22→14 | ⚠️ messy titles |
| ~~Mascotte~~ | Zürich | JSONP | — | ⏸ deferred |

¹ Zent's upcoming page is genuinely empty right now; I validated the selectors against its 85-event archive (parse clean, dates correct). It'll populate when they schedule shows.

**Cross-cutting notes**
- **Genres:** many venues expose no genre field at all (Dampfzentrale, Kaserne, Volkshaus, Treibhaus, Zent, Sous Soul, Turnhalle, Helsinki, Rote Fabrik currently). Those events will show with no style tags — visible, just not style-filterable. That's expected, not a bug.
- **No golden fixtures yet.** The golden suite *skips* these 14 (no committed fixtures), so `bin/rails test` is green. Capturing fixtures + goldens is the natural follow-up once you approve which to keep (note: `scrapers:capture_fixtures` needs a detail-link selector added for the two new click-into-detail venues, Sous Soul & Neubad).
- **New pattern: JSON scrapers.** 6 venues are JSON/REST, not HTML — a first for this codebase. They use the same `Agent` hooks; rows are Hashes instead of Nokogiri nodes, and the field extractors read keys. Mechanize fetches JSON cleanly (`Mechanize::File#body`). If you dislike this shape, that's a design call worth raising now.
- A live **dry-run harness** was added: `bin/rails "scrapers:dry_run[ClassName]"` → writes `tmp/dry_run/<venue>.json`, runs live, **never** touches the DB. Reusable for vetting any future scraper.

---

## Per-venue detail

### ✅ Dampfzentrale — Bern · `dampfzentrale.rb`
- **Source:** homepage `https://www.dampfzentrale.ch/` (server-rendered; `/spielplan` & `/veranstaltungen` are empty decoys).
- **Notes:** multidisciplinary house (lots of dance/theatre). Date is 2-digit-year `d.m.yy` → parsed explicitly (no `Time.zone.parse` silent-today). Cancellations read from the `.abgesagt` class. Multi-day runs list only their first date (detail page not fetched).
- **Sample:** `2026-06-12 19:00 · Tänzerische Einführung · mit Cosima Grand`

### ✅ Sous Soul — Bern · `sous_soul.rb`
- **Source:** Webflow homepage; clicks into each detail page (start time + year live there).
- **Notes:** list markup is **doubled** — deduped by detail href (34 unique, not 68). Year comes from the page `<title>` ("… | Jun 11, 2026 | …"), which is more robust than inferring it. The `06:00` start on "Guete Morge Frou Müller" is real (a morning disco).
- **Sample:** `2026-06-11 21:00 · IST ES WAHR, DASS SICH DIE ERDE… · Das Universum des Urs Lehmann`

### ✅ Zent — Bern · `zent.rb`  *(empty upcoming — see ¹)*
- **Source:** `https://restaurant-zent.ch/kulturprogramm` (the music side of the bimano complex; **not** bimano.ch).
- **Notes:** clean `<time>DD.MM.YYYY</time>` with year. No start time (German prose only) → defaults to date midnight. No genres. Validated against `/kulturprogramm/archiv` (85 rows parse correctly).

### ⚠️ Turnhalle — Bern · `turnhalle.rb`  *(needs your call — decision #1)*
- **Source I chose:** bee-flat `https://www.bee-flat.ch/programm/aktuell/`, filtered to rows whose date block names "Turnhalle". Music-only, 5 upcoming.
- **Alternative:** PROGR agenda `progr.ch/de/agenda` has cleaner ISO dates + year and a `span.venues` filter, **but** includes non-music Turnhalle events (football screenings etc.). Tell me which you want.
- **Notes:** bee-flat dates have no year → inferred (next-occurrence). **Sample:** `2026-10-10 20:30 · Mammal Hands`

### ✅ Le Singe — Biel · `le_singe.rb`  *(JSON)*
- **Source:** KartellCulturel `getEvents?…&location=1` JSON, paginated by `offset`. Clean ISO dates + curated genre arrays. Biel is canton BE.
- **Notes:** genres wired **consumption** (decision #2). **Sample:** `2026-06-14 17:00 · Milonga · genres: Dance`

### ⚠️ Treibhaus — Luzern · `treibhaus.rb`  *(verify scope)*
- **Source:** `https://www.treibhausluzern.ch/programm`. German "Monat TT, JJJJ" in `<time datetime>` (year present); real time from the adjacent span.
- **Heads-up:** I scrape the **whole** programme, which includes non-concert items (e.g. "Musikquiz", a feminist-strike warm-up). Filtering to concerts needs a per-event detail fetch for the category badge — happy to add if you want concerts only.

### ✅ Neubad — Luzern · `neubad.rb`  *(music-filtered)*
- **Source:** `https://neubad.org/veranstaltungen`; keeps only `Konzert`/`Klubnacht` rows (60→11), then clicks into the detail page for the year-qualified date + start time.
- **Sample:** `2026-06-13 21:00 · Bongdacity Rap for Refugees`

### ⚠️ Bar 59 — Luzern · `bar59.rb`  *(JSON, verify)*
- **Source:** public Firebase **Firestore** REST (the site is an empty Vue shell). Pages all docs, filters `isActive && date ≥ today`.
- **Heads-up:** (a) the collection includes summer-break **placeholder** entries titled "Sommerpause" — they'll appear as events; want them filtered? (b) no per-event page exists → events keyed on a synthetic `…/#event-<id>` URL. (c) relies on Firestore staying open-read (it is today). Genres are comma-split free text → consumption.
- **Sample:** `2026-06-12 20:00 · B59 Latin Groove · genres: Salsa, Bachata, Reggaeton`

### ✅ Südpol — Luzern · `suedpol.rb`  *(JSON, music-filtered)*
- **Source:** headless-WordPress REST `cms.sudpol.ch/?rest_route=/wp/v2/events&categories=4,13,63` (Konzert/Club/Sound). The Nuxt site itself is unscrapable. WP can only sort by *post* date, so I page all music events and filter on the ACF event timestamp → upcoming only (16).
- **Notes:** location declared "Luzern" (decision #3). Genres from ACF `tags` (consumption). **Sample:** `2026-06-12 23:00 · PLH · genres: Rap, Hip-Hop`

### ✅ Kaserne — Basel · `kaserne.rb`
- **Source:** `https://kaserne-basel.ch/de` (SvelteKit SSR). Filters `details.concert-type` (the venue also does dance/discourse). Title/ISO-date/time pulled from the `<add-to-calendar-button>` attributes (the visible title is an image).
- **Sample:** `2026-09-25 20:30 · Ebow` · only 5 upcoming (summer).

### ⚠️ Volkshaus — Basel · `volkshaus.rb`  *(verify filter)*
- **Source:** `https://volkshaus-basel.ch/programm/` (WordPress). Keeps `genre-musik` rows (20→6); date/time/title inline, no detail page.
- **Heads-up:** "musik" is coarse — it swept in **Daniel Sloss (comedy)** alongside jazz. Probably fine for a culture feed, but flagging. No per-event URL → keyed on `…/#event<id>`.

### ✅ Rote Fabrik — Zürich · `rote_fabrik.rb`  *(JSON, music-filtered)*
- **Source:** `https://kalender.rotefabrik.ch/api/events?categories=konzert` (clean public JSON; the site is a Vue SPA). 13 concerts, ISO dates + times.
- **Notes:** genre `tags` facet exists but is empty for current concerts (wired consumption for when they populate it). **Sample:** `2026-06-23 19:00 · SUNN O))) · Support: Natasha Grujović…`

### ✅ Dynamo — Zürich · `dynamo.rb`  *(JSON, music-filtered)*
- **Source:** Drupal/NodeHive JSON:API `dynamo.nodehive.app/jsonapi/node/event`, date-filtered server-side; keeps `Konzert`-tagged events (50→44) and maps the finer category tids to genres (Metal/Hip-Hop/Elektro/…), consumption.
- **Sample:** `2026-06-14 19:00 · Siyhakal + Grotto + Defused · genres: Hardcore/Punk`

### ⚠️ Helsinki Klub — Zürich · `helsinki.rb`  *(verify titles)*
- **Source:** homepage (Jimdo, server-rendered, inline programme). German weekday/day/month with **no year** → inferred. Start time regex-extracted from free-text `.showtime` (fixed an `&nbsp;` bug that was zeroing some times).
- **Heads-up:** titles are free-text and occasionally run words together (e.g. "LIZARD & the DEERlive recording"). No genres, no per-event URL (keyed on block id). Functional but the messiest of the batch.
- **Sample:** `2026-06-12 20:30 · Dino Brandão · + Shanice the Radish…`

### ⏸ Mascotte — Zürich — *deferred, decision #4*
- Rebranded to **Palais Mascotte**; events come from the **Nunight** platform via two-step JSONP (`event_widget_all_public` → ids, then `event_widget_single` per id, needs a `Referer` header). Currently only a "SOMMERPAUSE bis 06.08" placeholder, so I couldn't validate parsing. Ready to build on your word.

---

## When you're ready
Tell me which venues are 👍 (and your calls on decisions #1–#4). Then I'll:
1. apply any tweaks (concert filters, location strings, genre source, drop placeholders),
2. capture golden fixtures + tests for the keepers,
3. delete any you don't want,
4. and it's ready to merge → live on the next nightly sweep.

Nothing is pushed or in the database. The dry-run JSON for every venue is in `tmp/dry_run/`.
