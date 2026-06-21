# Bewegungsmelder integration — review notes

Branch `ole-bewegungsmelder`. Built autonomously 2026-06-21 on the plan you
approved (lean-permissive filtering; branch + real local sweep to browse).
**Not pushed to `main`, not deployed** — this is for your review first.

## TL;DR

- Bewegungsmelder is now a generic OLE source: `Scrapers::OleBewegungsmelder`
  (`aggregator: true`, `link_via: :source`). Feed: `https://bewegungsmelder.ch/oleexport/`.
- Local sweep ingested **28 upcoming events** → **23 visible, 5 hidden** by the
  music gate. That's the whole upcoming window right now; the "~7600 events"
  figure is mostly the historical archive back to 2012, which we correctly skip.
- Filtering lives in `db/genres.yml` (version-controlled), so the whole policy is
  a **reviewable diff** and deploys via `taxonomy:import_tree`.

## How to browse it locally

```
bin/rails server      # then open the events feed
```

The 23 visible events are tagged `OLE:Bewegungsmelder`. To re-pull / re-check:

```
bin/rails runner script/ole_dry_parse.rb Bewegungsmelder   # READ-ONLY, no writes
```

## Decisions I made (please verify)

### 1. Link target — your mid-flight question
You asked that links point at the venue's own event page, not bewegungsmelder.
**The feed can't reliably do that.** Its `<url>` field is inconsistent: for most
venues (e.g. Kulturhof, 17 events) it's only a bare *homepage*; for some (Heitere
Fahne) it's a real per-event deep link, but even there one points at `/menu` and
one at the homepage.

So I built a **hybrid**: link to the venue's `<url>` when it's a genuine
event-specific deep link (digit/id path or query string), otherwise fall back to
the bewegungsmelder per-event page — **never** a useless homepage. Result on the
live feed: **6 events link to the venue** (`dieheiterefahne.ch/events/…`), **22
to bewegungsmelder**. The bewegungsmelder URL is also the upsert key for those,
because it's the only stable, collision-free per-event identifier (the homepage
collides for same-venue/same-night shows).

*Easily flipped:* `link_via: :source` → all-bewegungsmelder; revert the
`venue_event_link?` preference → would mostly link to bare homepages (worse).

### 2. Filtering — lean-permissive, as you chose
Curated in `db/genres.yml`:

- **Hidden** (clear non-music — a listing carrying *only* these drops out):
  Theater, Ausstellung, Film, Kunst, Talk / Forum, Spoken Word, Kurse / Workshops,
  Spiel & Spass, Speis & Trank, Sport, Flohmi, Messe, Mundart. (Comedy, Lesung
  were already hidden.)
- **Blocked** (meaningless catch-alls — tag stripped on sight, like the existing
  `Konzert`/`Music`): Andere, Sonstiges.
- **Kept visible / `ignored`** (music-adjacent, shown per the permissive call):
  All Styles, Party, Tanz. (Festival was already `ignored`.)
- Real music genres (Jazz, Blues, Pop, Folk, Soul, Singer-Songwriter, …) pass
  through untouched and land in the curation queue to be filed into the tree.

I added the non-music tags from a broader 8-page sample too (not just the 28
current events), so future sweeps arrive pre-curated.

**The one judgement call worth a look:** several recurring **dance-class** entries
(the "Tanzen im Schlosshof" Lindy Hop / Salsa / Tango series, ~6 events) are
`Tanz`-only and therefore visible. That's the expected "a few dance events leak
in" cost of permissive. If you'd rather they not show, move `Tanz` from `ignored`
to `hidden` in `db/genres.yml` and re-run `taxonomy:import_tree` — drops ~6.

Two visible events are **genre-less** ("Summer Bigband", "…| Colibri") — they were
`Konzert`-only, and `Konzert` is blocked. By existing design a genre-less event
stays visible (`Event#hidden_by_genre?` returns false on empty). They're real
concerts, so showing them is correct; flagging so it's not a surprise.

### 3. Eventfrog rows — kept, not skipped
The old ledger note said "skip the Eventfrog-sourced rows." Investigated: in the
sample, `eventfrog` appears almost entirely in `<ticket_url>` (the ticket mirror
we never link to) — not in the data we use. Since we link via `<source_url>` /
venue deep-link, the eventfrog mirror never surfaces, so there's nothing to skip.
Kept them (real events; dedup + the music gate handle quality).

## Bugs found & fixed along the way

- **HTML entities in titles/categories weren't decoded** (the subtitle path
  already decoded via Nokogiri, the others didn't). `Speis &amp; Trank` was being
  minted as the junk genre `Speis &Amp; Trank`. Fixed in `clean_title` +
  `event_consumption_genres` (decode + squish), with a regression test. This was
  a latent bug affecting *all* OLE sources, not just bewegungsmelder.

## Upstream-data issue — FIXED

- **Heitere Fahne was resolving to canton VS, not BE.** Bewegungsmelder lists it
  under PLZ **3984** (genuinely Fiesch, Valais); Wabern's real PLZ is 3084 (Bern).
  Fixed with a hardcoded `CITY_CANTON_FIXES = { 'wabern' => 'BE' }` in the OLE
  adapter — keyed on locality so it corrects this place without remapping 3984
  for a real Fiesch event. Heitere Fahne now files under BE. Add a row there for
  any future venue an aggregator mis-tags via a typo'd PLZ.

## What changed (files)

- `app/services/scrapers/ole.rb` — `link_via` option + `event_base_url` /
  `venue_event_link?` (hybrid link), entity decode in `clean_title` /
  `event_consumption_genres`, `venue_domains` override for OLE aggregators, the
  Bewegungsmelder `SOURCES` entry.
- `db/genres.yml` — non-music dispositions (above).
- `config/venue_ledger.yml` — bewegungsmelder `defer/needs_work` → `consume`.
- Tests: `test/services/scrapers/ole_test.rb` (+3 tests),
  `test/fixtures/scrapers/ole/source_keyed.xml` (new fixture).

Full suite green: 466 runs, 0 failures (3 pre-existing skips). RuboCop clean.

## To deploy (after you approve)

1. Merge `ole-bewegungsmelder` → `main` (auto-deploys).
2. In the Render shell: `bin/rails taxonomy:import_tree` (applies the new
   dispositions to prod), then re-scrape or wait for the daily cron.
