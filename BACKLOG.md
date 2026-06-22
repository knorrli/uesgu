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

## UI polish

- **iOS PWA splash screen** — still missing. Android derives its splash from the
  manifest; iOS needs explicit `apple-touch-startup-image` link tags (per device
  size) or it launches to a blank screen. Needs artwork generation. The rest of
  the cold-start work is done: font preload, `theme-color` meta, service-worker
  app-shell cache, and Phosphor font subsetting (147 KB → 3.5 KB, regenerate via
  `script/subset_phosphor.py`) all shipped — see `docs/pwa-cold-start-proposal.md`.
  (See memory `project-pwa-install-affordance`.)

## Maybe-later (explicitly deferred)

- Session "Update the filter I just applied" soft-pointer.
- `featured`/`main_genre` flag + subtree-count browse ranking.

## Out of scope (not "incomplete")

- More scraper venues — candidate/evaluated venues live in `config/venue_ledger.yml` (defer/reject rows); discovery via `docs/discovery-design.md`.
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
