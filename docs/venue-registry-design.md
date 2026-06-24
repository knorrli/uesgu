# Venue registry — a single, code-controlled venue spine

Status: **in progress** (`feat/venue-registry`). This doc is the spec; it also
records the durable "we chose X / rejected Y because Z" rationale (which, per the
project conventions, belongs in `docs/`, not in issues).

## The problem

Venue identity is scattered across three mechanisms with three different rules:

| Source | Discovery | Identity / place | Curation (want it? music?) |
|---|---|---|---|
| Single-venue scrapers | code | code (`self.locations`) | code |
| PETZI | code (`Petzi::VENUES`/`DOMAINS`) | code | — |
| OLE aggregator (Bewegungsmelder) | **DB, at scrape time** | **faked from feed strings** | — |

Consequences we want gone:

1. **No single place to see or control venues.** "What did we reject and why",
   "which venue is sourced how (direct vs OLE; API vs RSS)", "turn this source
   off" — each answered differently, or not at all.
2. **`venue_ledger.yml` records *decisions per domain*, not *coverage per
   venue*.** A venue can be covered with no static record of it — Heitere Fahne
   reads `reject/js_only` yet is live via the Bewegungsmelder OLE aggregator. So
   `discovery.rake`'s `covered` set is blind to every aggregator-resolved venue
   (the gap `docs/feed-discovery-findings.md` flagged).
3. **`VenuePlace` auto-adds venues into the live taxonomy** with no approval, from
   messy feed strings, and never deletes — so a venue Bewegungsmelder stops
   listing is a ghost in the WHERE tree forever, and two spellings are two venues.

## Decision 1 — a single YAML registry (`config/venues.yml`) + one `Venue` value object

The registry is **one data file** — `config/venues.yml`, one row per venue
(identity + decision + aliases) — wrapped by **one** `Venue` PORO
(`app/models/venue.rb`) that loads it and exposes the computed API (`Venue.all`,
`consume?`, `placed?`, `matches?`, …). Identity and decision live in the data;
**sourcing is derived** from the live scraper/OLE/PETZI registries, so there is no
redundant wiring string to drift.

**Why this, and not a PORO-per-venue (we tried that first and reversed).** The
first cut gave each venue its own `Venues::<Name> < Base` class. With it built, the
promised advantages didn't materialize:

- The headline PORO win was "no drift, because the declaration *is* the wiring".
  But a venue still referenced its scraper by a **string** (`scraper: "Dachstock"`),
  exactly as drift-prone as a YAML field — the drift test was still required. The
  real no-drift only arrives in the (unbuilt, riskiest) sourcing-inversion phase,
  and even there the venue↔scraper link is just the **domain**, which both already
  carry.
- "Computed fields / behaviour / tests" don't need 53 classes — they need *one*
  `Venue` class wrapping the rows. Same methods, one file.
- "Matches the grain" cut the other way: scrapers are classes because they have
  *behaviour*; a rejected venue has none, so a class for it is pure ceremony. And
  OLE already generates scrapers from a plain **data array** (`Ole::SOURCES`) —
  the "config generates code" pattern here is data, not classes.
- 53 files (a blocked venue = 6 lines doing nothing) is real bloat; one greppable,
  diffable data file is leaner and is itself the inventory.

This is **not** the "disconnected YAML" we worried about earlier: the `Venue` class
*is* the connection to code (the API + behaviour live there, the drift test keeps
it honest). The YAML is just that object's serialized state — the same role
`Petzi::VENUES` and `Ole::SOURCES` already play as in-code data tables.

## Decision 2 — venues are a **closed allowlist**; genres stay an open firehose

Genres deliberately "collect everything, curate downstream, no closed-vocab gate".
Venues do the **opposite**: nothing reaches users without an approved venue. This
asymmetry is intentional and correct because the units differ:

- **Cardinality** — genres are an unpredictable long tail of thousands; venues are
  a tractable finite set (hundreds region-wide). Per-venue approval is feasible.
- **Predictability** — you can't enumerate genres up front; you can enumerate
  venues.
- **Blast radius** — an un-vetted *genre* token still rides an event from a vetted
  venue. An un-vetted *venue* is a **firehose** (a comedy club Bewegungsmelder
  lists would dump dozens of non-music events in). Gating the firehose at the
  venue is exactly right for a curated, music-focused product.

This also makes the system *more* consistent, not less: the ledger + `discovery
:report` flow is already "discover → human approves in a PR, never auto-enable".
The only thing that broke that rule was `VenuePlace` auto-adding. We bring
aggregator venues into line with how everything else already works.

## Decision 3 — discovery inbox (`VenueLead`) + lenient → strict migration

`VenuePlace` is repurposed from "taxonomy backdoor" to a read-only **discovery
inbox**: at the end of an aggregator run, every resolved venue that matches **no**
approved `Venue` (via its aliases) is recorded as a lead — name, source, upcoming-
event count, a sample URL — for a human to glance at and, if wanted, approve by
adding a one-line venue row to `config/venues.yml` (after which it drops off the
inbox automatically). The taxonomy no longer reads leads; it reads only approved
venues.

To migrate **without dropping coverage overnight**, an aggregator has a mode:

- `:lenient` (default, ship this) — ingest unmatched venues **and** record them as
  leads. Behaviour-preserving + the inbox starts filling.
- `:strict` — drop unmatched venues' events, record them as leads only.

Flip Bewegungsmelder to `:strict` only after its real venues are approved from the
inbox. No coverage is lost until you decide it is.

## The model

`config/venues.yml` — identity + decision only:

```yaml
venues:
- domain: dachstock.ch
  name: Dachstock
  disposition: consume
  place: { city: Bern, canton: BE }
  checked: 2026-06-21
  aliases: { petzi: [dachstock], ole: [api.dachstock.ch] }
- domain: dieheiterefahne.ch
  name: Heitere Fahne
  disposition: reject
  reason: js_only
  checked: 2026-06-17
  # to enable later via the aggregator: flip to `disposition: consume` and add a
  # hinto alias for the raw <location> name(s) the feed emits for this venue.
```

Sourcing is **not** written here — `Venue#sourcing` / `venues:inventory` derive it
from the live registries (`Scrapers::All`, `Ole::SOURCES`, `Petzi::DOMAINS`): a
`:direct` source is a bespoke scraper whose `venue_domains` include the domain;
`:ole`/`:petzi` come from those constants. Per-source enable/disable switches and
the aggregator `matches` list are added to the YAML only when the behavioural PRs
wire them.

## Reconciliation with the live scrapers

Scrapers keep declaring their own place (no inversion yet); the registry is the
source of truth for **decisions and discovery**, kept honest by the existing drift
test — re-pointed from `venue_ledger.yml` to `config/venues.yml` (same rules: every
`consume` venue backed by a live scraper; every scraped domain has a `consume`
venue; reasons well-formed; aliases unique).

## Phasing

Split so the safe, non-behavioural foundation can land unsupervised, and the
visible/behavioural changes get review + a live sweep.

- **PR 1 — foundation (this branch).** `config/venues.yml` + the `Venue` model +
  every venue migrated from the ledger/PETZI/OLE; `Discovery::Ledger` is a read-only
  projection of it; `venue_ledger.yml` retired. The drift test reconciles the
  registry against the live scrapers (same rules), and `venues:inventory` shows the
  derived sourcing. Delivers the see/decide wants — enable/disable venues (status),
  rejected+why, sourcing-by-means — as a readable, single-file, code-controlled
  list. **No behaviour changes; all existing tests stay green.** (Per-source
  enable/disable switches land with PR 2/3, when there's wiring to switch.)
- **PR 2 — taxonomy + inbox (with review).** Point `Location` at the registry
  (severs `VenuePlace` from the WHERE tree); add the `VenueLead` discovery inbox
  and the aggregator `:lenient`/`:strict` mode. Behavioural + visible (it decides
  which venues appear and which aggregator events ingest), so it wants a live
  sweep to confirm what changes before flipping anything to `:strict`.
- **PR 3 — invert sourcing.** Scrapers read their place *from* the linked venue
  (removes the last duplication; the drift test becomes a safety net, not a
  necessity). Touches every scraper, so done supervised.
- **PR 4 — admin inbox UI** over `VenueLead`, ranked by event count, + the
  generated inventory artifact.

## Rejected / not doing

- **A PORO-per-venue registry** — built it, reversed off it: it didn't earn the
  53-file cost (see Decision 1). One YAML file + one `Venue` class gives the same
  single-source-of-truth, computed API, and drift safety, leaner.
- **Storing sourcing/wiring in the registry** — a `scraper:` string is redundant
  with the scraper's own `venue_domains` and would drift; sourcing is derived.
- **Dynamic venue addition from aggregators** — deliberately traded away for a
  fully-managed list (Decision 2); the inbox keeps discovery cheap.
- **Inverting every scraper in PR 1** — too much surface to land unsupervised;
  PR 3.
