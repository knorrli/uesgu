# üsgu — Backlog

> Single source of truth for **what's left**. If an open item isn't here, it
> isn't tracked. This file carries open work only — not history. üsgu is a
> **personal tool**: functional completeness is met; remaining work is polish
> plus a few open items.

## Scrapers

- **Capture richer fields some sources expose but we drop.** Blocked on a schema
  decision — these need **new event columns first** (`price` / `lineup` /
  `description` / `image`, none exist today): **Bad Bonn** has `data-price`;
  **bar59** (Firestore) has `artists` (lineup/support), `htmlText` (description),
  and `picture` (image). Once the columns are decided, re-run the
  `/admin/scraper_coverage` audit across the rest of the scrapers for similar
  droppable fields. (Genuinely-absent fields are already declared in-code via
  `field_gaps` and render as n/a in the matrix — don't re-audit those.)

## UI polish

- **General mobile-first sweep** of the app — ongoing direction, not a discrete
  ticket. Enforce the visual invariants: what's clickable is unambiguous; one
  visual representation per element; green only ever means "interested" (heart =
  saved shows). See memory `project-screenshot-design-review`.
- **Slow PWA start / splash screen** — cold start is sluggish; no splash handling
  yet. (See memory `project-pwa-install-affordance`.)

## Maybe-later (explicitly deferred)

- Session "Update the filter I just applied" soft-pointer.
- `featured`/`main_genre` flag + subtree-count browse ranking.

## Out of scope (not "incomplete")

- More scraper venues — candidate/evaluated venues live in `config/venue_ledger.yml` (defer/reject rows); discovery via `docs/discovery-design.md`.
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
