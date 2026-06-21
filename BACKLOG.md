# üsgu — Backlog

> Single source of truth for **what's left**. If an open item isn't here, it
> isn't tracked. Reconciled against code on 2026-06-20 (the old punch list and
> session backlog were ~20 items already shipped — all removed).
>
> üsgu is a **personal tool** — built until it feels useful, not an MVP to
> validate. **"Complete" = functional completeness first, then a UI polish
> pass.** Functional completeness is met; remaining work is polish + a few open
> bugs.

## Where we are (live on `main`)

- **Data ingestion** — venue scrapers + PETZI aggregator with non-destructive
  dedup, genre-tree taxonomy + normalization, location hierarchy
  (venue/city/canton), cancellation + reschedule detection, discard rules,
  scrape-run admin with drop-to-zero abort alerting.
- **Browsing** — events feed (list + calendar), What/Where/When filter on the
  genre tree + date presets, saved-show day markers, interest highlighting
  (saved-filter-derived), light/dark theme, de/en/fr, installable PWA.
- **Accounts** — invite-only signup, username/password, optional email, settings.
- **Saved filters** — save any What/Where/When filter (funnel control, fingerprint
  deduped); optional per-filter notification (in-app inbox, web push, email via
  Resend). Generalises the retired notification-rules + Interests/Favorites.
- **Saved shows** — single-event save, "My saved shows", ICS subscription feed,
  midday "your saved show is tonight" reminder (toggle on the saved-shows page).
- **Admin** — dashboard, users, invitations, scrape runs, genre-tree + location
  catalogues, per-event manual overrides, genre curation (unplaced) queue,
  discard rules.

## Open

### Scrapers

- **Maximize collected info per scraper.** Audit each scraper for fields it
  *could* be capturing but isn't, using the `/admin/scraper_coverage` matrix to
  spot low fill-rates. First-pass audit (2026-06-20): the 0%-genre venues
  (Bad Bonn, Böröm, Dampfzentrale) and bar59's 0% subtitle are **genuine** — the
  sources don't expose those fields, not bugs. The real finds are *richer fields
  some sources expose but we drop*: **Bad Bonn** has `data-price`; **bar59**
  (Firestore) has `artists` (lineup/support), `htmlText` (description), and
  `picture` (image). Capturing these needs **new event columns first**
  (`price` / `lineup` / `description` / `image` — none exist today), so this is a
  schema decision, not just a parser tweak. Re-run the audit across the rest of
  the scrapers once that's decided.
- **Curate the genres minted after the gate removal.** With the
  consumption/discovery gate gone, freetext sources now mint every token they
  emit, so the unplaced-genre queue will fill on the next sweep — including known
  noise like **docks** origin codes (`US`/`CH`) and Mahogany prose. Sweep the
  queue (file / alias / block) and give the docks codes their own origin facet or
  a block (see memory `project-docks-scraper-country-as-genre`). Watch the volume
  via `/admin/scraper_coverage` distinct-genre counts.

- **Consume OLE feeds as a generic source (Open Linked Event Data).** *Core
  shipped on branch `ole-ingestion` (2026-06-21), pending merge + deploy.*
  `Scrapers::Ole` is a generic, config-driven `Agent` subclass: a `SOURCES` list
  generates one registered scraper per feed — **new source = a URL, not code**.
  Handles all the POC's skipped gotchas: `date_start >= today` filter,
  `<meta><next_url>` pagination, multi-show → N events (venue `<url>` + show-date
  key), per-event aggregator location with PLZ→canton (`Scrapers::SwissPostcode`),
  trailing-colon title cleanup. Event URL is the venue's own `<url>`, never the
  `<ticket_url>` mirror. Six robots-OK single-venue Bern feeds ship and were
  live-verified (Dachstock, Klangkeller, La Cappella, Casino Bern, Lichtspiel,
  Stattland); Dachstock proves `Scrapers::Dedup` absorbs PETZI overlap. Golden
  tests + `script/ole_dry_parse.rb` (read-only) included. Remaining follow-ups:

  - **Robots decision for robots-disallowed feeds.** Birdseye + BeJazz expose OLE
    exports but `robots.txt` disallows our UA. Held pending a deliberate per-venue
    opt-out call (cf. `Scrapers::BadBonn`). BeJazz was the intended aggregator
    proof; aggregator support is implemented + tested regardless. Listed in
    `Scrapers::Ole::DEFERRED`.
  - **Bewegungsmelder aggregator — BUILT, pending review + deploy** (branch
    `ole-bewegungsmelder`, 2026-06-21). `Scrapers::OleBewegungsmelder`
    (`aggregator: true`, `link_via: :source` — keys on per-event `<source_url>`,
    prefers a real venue deep link when the feed gives one). Lean-permissive
    non-music filtering curated in `db/genres.yml`. Ledger flipped to `consume`.
    Review `FINDINGS-bewegungsmelder.md`, then merge + run `taxonomy:import_tree`
    in prod. **Open verify item:** `Tanz`-only dance-class series shows under the
    permissive policy (flip `Tanz`→hidden to drop it); Heitere Fahne files under
    VS due to an upstream PLZ typo (3984) — admin location fix if wanted.
  - **Messy aggregates.** Konzerte Bern (0 genres + address jammed into `<name>` →
    needs address-in-name cleanup) and Hinto ALL (46 venues) deferred.
  - **Retire fragile scrapers where OLE overlaps** (e.g. the bespoke Dachstock
    HTML scraper) — evaluate once OLE has run a few sweeps.

  Full schema + source list + gotchas in memory `project-open-event-data-avenues`.
  (Out of scope: admin-UI toggle, images, Eventfrog.)

### UI polish

- **General mobile-first sweep** of the app — ongoing direction, not a discrete
  ticket. Enforce the visual invariants: what's clickable is unambiguous; one
  visual representation per element; green only ever means "interested" (heart =
  saved shows). See memory `project-screenshot-design-review`.
- **Slow PWA start / splash screen** — cold start is sluggish; no splash handling
  yet. (See memory `project-pwa-install-affordance`.)

### Discuss / experiment

- **Filter menu floats over content instead of pushing it down.** Currently
  opening the filter shifts the results list downward. Experiment with an
  overlay/floating panel that sits *above* the content (no layout push). Decide
  the interaction (anchored popover vs. sheet, desktop vs. mobile) before
  committing — relates to the existing reserved-summary-row layout work.

### Maybe-later (explicitly deferred)

- Reschedule **state-change-back** detection — core reschedule marking ships;
  detecting "was rescheduled, now back to the original date" doesn't.
- Session "Update the filter I just applied" soft-pointer.
- `featured`/`main_genre` flag + subtree-count browse ranking.

## Out of scope (not "incomplete")

- More scraper venues — candidate/evaluated venues live in `config/venue_ledger.yml` (defer/reject rows); discovery via `docs/discovery-design.md`.
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
