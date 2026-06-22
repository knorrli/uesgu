# üsgu — Backlog

> Single source of truth for **what's left**. If an open item isn't here, it
> isn't tracked. This file carries open work only — not history. üsgu is a
> **personal tool**: functional completeness is met; remaining work is polish
> plus a few open items.

## Scrapers

- **Capture richer fields some sources expose but we drop.** Blocked on a schema
  decision — these need **new event columns first** (`price` / `lineup` /
  `description` / `image`, none exist today). **Audit done + schema proposal
  drafted: `docs/richer-fields-proposal.md`** — confirmed dropped fields per
  scraper (bar59 is richest: artists/htmlText/picture; plus Bad Bonn price, OLE
  + PETZI description, Mahogany Hall price), recommended migration, and the one
  real open decision (image hotlink vs proxy vs skip, a privacy call). Answer the
  4 open decisions in that doc and the wiring is mechanical. (Genuinely-absent
  coverage fields are declared in-code via `field_gaps` — don't re-audit those.)

## Maybe-later (explicitly deferred)

- **"Party spotlight" cones — asymmetric / dynamic light mark.** Make the mark's
  light-cones feel like live coloured spotlights rather than the static symmetric
  splay. Two distinct directions: (a) an **asymmetric static logo redesign** —
  brand change touching every icon surface (`icon.svg`, `icon-light.svg`, the PWA
  PNGs, and the generated splash via `script/generate_ios_splash.rb`); or (b) an
  **in-app animated loader** (HTML/CSS/SVG, rendered after the PWA boots) — the
  only way to get genuinely dynamic motion, since the iOS splash is a static
  pre-boot image and cannot animate. Pick the direction first; they're separate
  efforts.
- Session "Update the filter I just applied" soft-pointer.
- `featured`/`main_genre` flag + subtree-count browse ranking.

## Out of scope (not "incomplete")

- More scraper venues — candidate/evaluated venues live in `config/venue_ledger.yml` (defer/reject rows); discovery via `docs/discovery-design.md`.
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
