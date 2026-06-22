# üsgu — Backlog

> Single source of truth for **what's left**. If an open item isn't here, it
> isn't tracked. This file carries open work only — not history. üsgu is a
> **personal tool**: functional completeness is met; remaining work is polish
> plus a few open items.

## Scrapers

- **Capture richer fields some sources expose but we drop.** Two slices already
  shipped (genre-mining + the subtitle→description rename, below). What remains is
  the **price** and **image** capture — `price` and `image_url` columns don't exist
  yet, blocked on a schema decision. **Audit + proposal: `docs/richer-fields-proposal.md`**
  (note: the proposal's separate `description`/`lineup` columns are SUPERSEDED — see
  the rename below; only price + image remain). Bad Bonn / Mahogany Hall expose a
  price; the one real open decision is **image hotlink vs proxy vs skip** (a privacy
  call — see the doc). Until then, the per-source **curate** follow-up (next bullet)
  is the live work. (Genuinely-absent coverage fields are declared in-code via
  `field_gaps` — don't re-audit those.)
    - **Shipped — ingest-time genre-mining from dropped prose.** The description
      text at five genre-less venues (kairo, helsinki, bad_bonn, volkshaus,
      rote_fabrik) is now scanned at ingest for genre names that ALREADY exist in
      the taxonomy and attached as taggings — match-only, mints nothing
      (`Genre.names_in_prose` + the `event_genre_prose` opt-in hook; everyday-word
      homographs excluded via `PROSE_MINING_STOPWORDS`). Mined genres attach at
      scrape time and `build_event` re-derives the music gate (`hidden`) in the same
      pass, so existing events pick them up on their next scrape with no separate
      backfill — a console `Event.find_each(&:recompute_visibility!)` forces it sooner.
    - **Shipped — renamed `subtitle` → `description`.** The single secondary-text
      column had drifted into a general "best text we have" field (tagline / support
      line / lineup / first blurb paragraph / title-dup). Renamed it instead of
      adding a 2nd column, so `description` + `lineup` from the proposal collapse
      into one curated-per-source field. The B1 mining hook is `event_genre_prose`
      (distinct from the displayed `event_description`). The card's presentational
      class is now `.event-description` too (the isc/docks `.event-subtitle` venue
      selectors are unrelated and stay).
    - **Open — curate what fills `description` per source.** Now that the field is
      general, improve its content per scraper: kill nouveau_monde's title-dup,
      fill the empties (kairo/volkshaus have prose we currently only mine), prefer a
      real blurb over a restated title where the source offers one. Pure scraper-hook
      work, no schema.

## Maybe-later (explicitly deferred)

- **"Party spotlight" animated loader.** An in-app animated loader (HTML/CSS/SVG,
  rendered after the PWA boots) that brings the mark's spotlight cones to life —
  genuinely dynamic motion the static iOS splash can't do (it's a pre-boot image).
  The static asymmetric mark already ships via `script/generate_icons.rb`; this is
  the separate motion follow-up.
- Session "Update the filter I just applied" soft-pointer.
- `featured`/`main_genre` flag + subtree-count browse ranking.

## Out of scope (not "incomplete")

- More scraper venues — candidate/evaluated venues live in `config/venue_ledger.yml` (defer/reject rows); discovery via `docs/discovery-design.md`.
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
