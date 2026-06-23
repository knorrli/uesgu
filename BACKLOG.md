# üsgu — Backlog

> Single source of truth for **what's left**. If an open item isn't here, it
> isn't tracked. This file carries open work only — not history. üsgu is a
> **personal tool**: functional completeness is met; remaining work is polish
> plus a few open items.

## In progress

- **Datenschutz wording is not lawyer-reviewed.** The `/privacy` (Datenschutz) copy
  in de/fr/en is a best-effort revDSG notice — sanity-check before relying on it.

- **Clean repo of unused deploy plumbing.** We're on Render, not Kamal, but the
  Kamal scaffolding is still in the tree: `.kamal/` (hooks + secrets),
  `config/deploy.yml`, `bin/kamal`. Remove the dead Kamal plumbing (and any
  Docker/Kamal-only bits no longer referenced) so the repo reflects the actual
  Render deploy path. Verify nothing in CI / `render.yaml` references them before
  deleting.

- **Optimize Render build by excluding unnecessary dirs/files.** The Render build
  currently ships the whole repo. Trim what gets uploaded/built — e.g. via
  `.renderignore` and/or `.slugignore` (none present today) — excluding things like
  `test/`, `docs/`, screenshots/scratch, and other non-runtime assets so builds are
  smaller and faster. Confirm exclusions don't drop anything the build/runtime needs.

- **Merge open Dependabot PRs.** Six open at time of writing: #2 actions/upload-artifact
  4→7, #3 actions/checkout 4→7, #4 ruby-minor-and-patch group (16 updates), #5 discard
  1.4.0→2.0.0 (major — check changelog), #6 brakeman 7.0.2→8.0.5, #7 puma 6.6.0→8.0.2
  (major — check changelog). Review/CI each, watch the majors (discard, puma), merge.

## Maybe-later (explicitly deferred)

- **Turbo progress-bar CSP console error (cosmetic).** On prod every page logs a
  CSP violation: `style-src-elem` blocked at `turbo.es2017-esm.js` →
  `installStylesheetElement`. Cause: Turbo's navigation progress bar injects one
  inline `<style>` (`.turbo-progress-bar`, the 3px top loading bar) into `<head>`.
  Turbo *does* stamp our `<meta name="csp-nonce">` nonce onto that element, but our
  `style-src` directive lists no nonce (only `script-src` is in
  `content_security_policy_nonce_directives`), so the browser has nothing to match
  → blocked. Impact is cosmetic only: the bar is unstyled/invisible (its
  width/opacity are CSSOM property writes, which CSP doesn't police, so no other
  errors); navigation is unaffected. The only cost is the recurring console noise.
  Fix (one line): add `style-src` to `content_security_policy_nonce_directives` in
  `config/initializers/content_security_policy.rb` → header becomes
  `style-src 'self' 'nonce-…'` and Turbo's nonce'd `<style>` is accepted, with no
  `'unsafe-inline'`/`'unsafe-hashes'` loosening. **Trade-off:** this re-introduces a
  nonce on `style-src`, which was deliberately dropped (the `style-src 'self'`
  "no inline styles, all CSS external" stance). Alternatives: a CSP hash of the
  static CSS (brittle — the rule interpolates `animationDuration`, breaks on Turbo
  upgrades) or just living with the console noise. Nonce is the clean option.

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
