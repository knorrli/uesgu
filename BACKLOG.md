# üsgu — Backlog

> Single source of truth for **what's left**. If an open item isn't here, it
> isn't tracked. This file carries open work only — not history. üsgu is a
> **personal tool**: functional completeness is met; remaining work is polish
> plus a few open items.

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
- Richer event fields (`price` / `image`) — **rejected.** Image hotlinking leaks
  the viewer's IP to every venue (against the privacy-first ethos) and proxying is
  not worth the cost for a personal tool; price adds little. The proposal's other
  two fields shipped differently: `description` + `lineup` collapsed into the single
  curated `description` field (the `subtitle`→`description` rename + per-source
  curation). Audit retained for reference at `docs/richer-fields-proposal.md` (now
  closed). Genre-mining from dropped prose also shipped (`event_genre_prose`).
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
