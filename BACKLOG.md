# üsgu — Backlog

> Single source of truth for **what's left**. If an open item isn't here, it
> isn't tracked. This file carries open work only — not history. üsgu is a
> **personal tool**: functional completeness is met; remaining work is polish
> plus a few open items.

## In progress

- **Datenschutz wording is not lawyer-reviewed.** The `/privacy` (Datenschutz) copy
  in de/fr/en is a best-effort revDSG notice — sanity-check before relying on it.

## Maybe-later (explicitly deferred)

- **Upstream Turbo scroll bug — workaround shipped, PR optional.** A
  `data-turbo-action="advance"` turbo-frame navigation (our calendar's open-day
  URL) permanently sets Turbo's internal `view.forceReloaded`, which then silently
  disables scroll-to-top for **every** later Drive visit — the intermittent "feed
  pagination doesn't scroll to the top" bug. Worked around in
  `app/javascript/application.js` (reset the flag on `turbo:before-render`); guarded
  by `test/system/feed_pagination_scroll_test.rb`. Root cause is **upstream and
  unfixed in the latest Turbo** (8.0.13 here; still broken on 8.0.23 / `main` —
  `forceReloaded` is only ever initialised, never reset). Tracked upstream as
  [hotwired/turbo#1344](https://github.com/hotwired/turbo/issues/1344) (original,
  2024-12) and [#1526](https://github.com/hotwired/turbo/issues/1526) (root-cause
  writeup); both open, maintainer interest but no PR. Follow-ups: (a) optionally
  submit the trivial fix as a PR (reset `forceReloaded` at `Visit#start` + a
  functional test); (b) once upstream ships a fix, delete our workaround + its test.

- **"Party spotlight" animated loader.** An in-app animated loader (HTML/CSS/SVG,
  rendered after the PWA boots) that brings the mark's spotlight cones to life —
  genuinely dynamic motion the static iOS splash can't do (it's a pre-boot image).
  The static asymmetric mark already ships via `script/generate_icons.rb`; this is
  the separate motion follow-up.
- **User-contributed event capture** — demand-side coverage: let a user
  voluntarily hand üsgu an unstructured event (snap a street poster; paste a
  WhatsApp concert tip) → extract → dedup → provisional event. One funnel, two
  input adapters; poster-photo path goes first. Ethos-critical: capture the
  *event*, never *monitor* the WhatsApp group. Idea note + rough poster pipeline
  in [`docs/user-event-capture.md`](docs/user-event-capture.md).
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
