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

- **"Party spotlight" animated loader (deferred half of the cone idea).** The
  asymmetric static redesign **shipped** — the mark now has asymmetric,
  rounded-pool "party spotlight" cones, and every icon artifact regenerates from
  one source via `script/generate_icons.rb`. What remains deferred is an **in-app
  animated loader** (HTML/CSS/SVG rendered after the PWA boots) for genuinely
  dynamic motion — the iOS splash is a static pre-boot image and cannot animate.
  Separate effort.
- Session "Update the filter I just applied" soft-pointer.
- `featured`/`main_genre` flag + subtree-count browse ranking.

## Out of scope (not "incomplete")

- More scraper venues — candidate/evaluated venues live in `config/venue_ledger.yml` (defer/reject rows); discovery via `docs/discovery-design.md`.
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
