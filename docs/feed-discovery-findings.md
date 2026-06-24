# Feed-discovery sweep & the venue-sourcing inventory gap (2026-06-24)

**Why this exists.** Continuing the hunt for higher-value ingestion than per-venue
HTML scraping (see `docs/open-event-data-research.md`), we built a generic
reconnaissance tool — `script/feed_discovery.rb` — and swept every domain in
`config/venue_ledger.yml` for a machine-readable, no-JS event source (iCal,
WP REST, `schema.org/Event` JSON-LD, RSS, sitemap), robots-respecting.

Running it surfaced **two** things: a list of concrete per-venue directions
(§3), and a **structural gap** that has to be closed before we act on them (§1).

---

## 1. The headline: the ledger records *decisions*, not *coverage* ⚠️

`venue_ledger.yml` answers "have we decided what to do about this **domain**?"
It does **not** answer "which **venue** is fed by which **source(s)**?" Those are
different questions, and the difference is load-bearing because **coverage is
many-to-many**: one venue can arrive through several sources, and a venue can be
covered **without any static record of it**.

**Worked example — Heitere Fahne.** Its ledger row is
`dieheiterefahne.ch → reject/js_only` (a Vue SPA; start time + genre sit behind a
private `/ajax/` — rejected on ethics). The feed-discovery tool agreed: "nothing
machine-readable on its own site." **But its events are already in üsgu**, arriving
through the **OLE Bewegungsmelder** aggregator, which resolves the venue per event
from the feed's `<location>`. The "reject" decision is about its *own website*;
the *venue* is covered elsewhere. The tool — and the sweep — probe domains in
isolation, so they answered the wrong question for this venue.

**Why nothing records it.** From the live scraper registry:

- A single-venue scraper declares `venue_domains = ["its-domain.ch"]`.
- **PETZI** (member-enumerating aggregator) declares its venues **statically**
  (`Scrapers::Petzi::DOMAINS.values`) — so PETZI-covered venues *are* visible.
- An **OLE per-event aggregator** (Bewegungsmelder, BeJazz) declares
  `venue_domains = [its own feed host]` **only** (`app/services/scrapers/ole.rb`).
  The venues it carries are resolved at scrape time into `VenuePlace` rows and
  intentionally kept out of the static declaration (`#aggregator?` keeps them out
  of the location taxonomy too).

Consequence: `lib/tasks/discovery.rake`'s coverage set —
`covered = Scrapers::All.scrapers.values.flat_map(&:venue_domains)` — is **blind
to every venue an OLE aggregator resolves per event.** Heitere Fahne (and any
other Bewegungsmelder-only venue) is covered in the *data* (post-sweep
`VenuePlace` rows) but invisible in any *static inventory*.

So before trusting any "uncovered / build a scraper" conclusion, we must be able
to ask: *is this venue already arriving via an aggregator?*

---

## 2. Prerequisite next step — build a venue inventory (do this first)

Before acting on §3, produce a **full venue inventory**: every venue we surface,
and which source(s) feed it. It must fold in the three coverage mechanisms:

1. **Direct** single-venue scrapers (`venue_domains`).
2. **PETZI** static member map (`Scrapers::Petzi::DOMAINS`).
3. **OLE per-event aggregators** — the venues actually resolved into `VenuePlace`
   on a real sweep (Bewegungsmelder, BeJazz). This is the part nothing currently
   enumerates statically; it has to be read from resolved data.

Open questions the inventory should answer:

- Which venues are covered by **more than one** source (and is that deduping
  cleanly via `canonical_event_id`)?
- Which "reject/defer" ledger domains are nonetheless **covered via an
  aggregator** (like Heitere Fahne)? Those rows are misleading as written.
- Which aggregator-resolved venues have **no own-domain ledger row at all**?
- Do we want venue meta-information (canton/city, own-site URL, source list) as a
  first-class record, rather than derived ad hoc?

**Implementation hint:** `discovery.rake` already computes a `covered` set and a
drift check; the inventory is its natural extension — add the aggregator-resolved
`VenuePlace` venues so coverage reflects reality, then emit a venue→sources map.

Until this exists, treat §3 as **candidate directions, not work orders.**

---

## 3. Feed-discovery sweep results — 53 domains (provisional)

Tool: `script/feed_discovery.rb` (POC, persists nothing). Legend: ★ time-bearing
structured feed found · ✓ weak signal (RSS/sitemap, no clean time source) · ·
nothing machine-readable. **Counts: ★8 ✓32 ·13.**

> ⚠️ Every direction below is **pending reconciliation against the §2 inventory.**
> "Build a scraper" especially: first confirm the venue isn't already arriving via
> an aggregator (the Heitere Fahne trap). E.g. Marians is a Bern venue — check it
> isn't already coming through Bewegungsmelder before building anything.

### A. Build new coverage — not (apparently) scraped

| Venue | Direction | Evidence |
|---|---|---|
| **Marians Jazzroom** `mariansjazzroom.ch` | Build scraper: sitemap → detail-page `Event` JSON-LD | `reject/js_only`, but detail pages are SSR'd with clean `startDate`, robots-allowed. Verify not already via aggregator first. |

### B. Re-evaluate — access changed, caveat stands

| Venue | Direction | Evidence |
|---|---|---|
| **BeJazz** `bejazz.ch` | Re-evaluate (don't auto-build) | Robots-allowed wholesale iCal `/bejazz.ics` (13 future events) — the `defer/robots` was about its OLE host, not this. **But** BeJazz is itself a roving promoter (already an OLE aggregator source); the dedup/scatter concern is unchanged. |

### C. Improve — switch an existing HTML scraper to a clean feed (optional)

The distinction that matters: a **wholesale** feed (whole programme in one pull)
is worth switching to; a **per-event `.ics`** ("add to calendar" on one show) is not.

| Venue | Direction | Evidence |
|---|---|---|
| **Rössli** `souslepont-roessli.ch` | Switch to `?ical=1` (improve) | WordPress + The Events Calendar **wholesale** iCal (25 future VEVENTs). Not in PETZI → bespoke scraper is the sole source, so a structured feed is a real robustness win. |
| **Le Singe** `kartellculturel.ch` | Switch to detail JSON-LD (improve) | Clean `Event` JSON-LD with `startDate`; not in PETZI → sole source. |
| Gaskessel `gaskessel.ch` | No action | `.ics` found is **per-event**, not wholesale; already PETZI-covered. |
| Helsinki `helsinkiklub.ch` | No action | Per-event `.ics` only; already PETZI-covered. (Its robots blocks GPTBot — not us — confirming the opt-out detector works.) |

### D. Keep current scraper — no action (consume venues, working)

No cleaner time-bearing feed than what we already ingest:

- **PETZI spine + bespoke (stable):** `dachstock` (also OLE), `docks`, `fri-son`,
  `isc-club`, `cafe-kairo`, `kiff`, `kofmehl`, `neubad`, `sedel`, `nouveaumonde`,
  `treibhausluzern`, `boeroem`.
- **Bespoke HTML, no feed, fine as-is:** `badbonn`, `bar59` (Grav),
  `dampfzentrale`, `dynamo`, `kaserne-basel`, `mahogany`, `muehlehunziken`,
  `rotefabrik`, `saegegasse`, `schuur` (TYPO3), `sous-soul`, `sudpol`, `bee-flat`,
  `volkshaus-basel`, `restaurant-zent`.
- **`bewegungsmelder`** — already our OLE aggregator; RSS/sitemap add nothing.

Caveat: the tool samples ≤3 detail pages for JSON-LD, so it can miss structured
data on a few of these. Re-probe a specific venue by hand if its scraper later
gets fragile.

### E. Stays rejected — feed exists but **content-blocked**, not access-blocked

Confirms the reject reasons are honest (it's *fit*, not *reachability*):

- ★ rich feeds, still non-music: `breitsch-traeff` (132-event iCal),
  `kulturdietikon` (iCal + Tribe REST + JSON-LD) — civic/Kleinkunst agendas.
- ✓ non-music, no action: `la-cappella`, `futurina`, `klangkeller-bern`,
  `lichtspiel`, `refbern`, `stattland`, `mobilservice`.
- `konzerte-bern` (`feed_quality`) — weak RSS only; prior call stands.

### F. Stays rejected/deferred — no usable path confirmed

| Venue | Status | Finding |
|---|---|---|
| `dieheiterefahne` | js_only — **but covered via Bewegungsmelder** (see §1) | Own site dead; venue already ingested via the aggregator. |
| `prozess` | js_only — dead | Empty SPA shell. |
| `mokka` | js_only — keep | Ecwid JS widget; sitemap only. |
| `ducommerce-biel` | js_only — keep | Squarespace, but no Events collection (sitemap ~0 event-ish); RSS is site-wide blog. |
| `onobern` | no_date — keep | EventON (admin-ajax, no clean REST); RSS carries no event date. |
| `cafehueber` | no_date — keep | WordPress RSS only, no time source. |
| `casinobern` | inactive — keep | Generic `event` CPT exposes post-dates only; OLE feed stuck on 2019. |
| `birdseye` | defer/robots — keep | Nothing robots-allowed surfaced. |

---

## 4. The tool — `script/feed_discovery.rb`

Generic; point it at any domain or sweep the ledger. Probes (strongest first):
iCal/`.ics`, WP REST (The Events Calendar via `/wp-json/wp/v2/types` detection),
`schema.org/Event` JSON-LD on a sampled sitemap detail page, RSS/Atom (incl.
`<link>` autodiscovery), sitemap event-URL counts. Reports robots posture with an
AI/bot opt-out flag (honours stated intent, not just whether a rule names our UA).

```sh
ruby script/feed_discovery.rb                      # sweep the whole venue ledger
ruby script/feed_discovery.rb mariansjazzroom.ch   # recon any candidate domain
ruby script/feed_discovery.rb --js                 # only js_only / no_date rejects
```

**Known blind spots (by design):**

- **Domain-in-isolation** — it cannot see aggregator coverage (the §1 gap). This
  is why §3 is provisional.
- **Subdomain feeds** aren't probed (e.g. Dachstock's good feed lives on
  `api.dachstock.ch`, so it reads only "weak" here).
- It samples **one** detail page, enough to flag "buildable," not to validate
  every event.

See also: `docs/open-event-data-research.md`, the Bewegungsmelder build note in
`config/venue_ledger.yml`, and the `project-open-event-data-avenues` /
`project-venue-discovery-ledger` memories.
