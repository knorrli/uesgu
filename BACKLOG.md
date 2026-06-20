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

- **Surface scraper errors in the logs.** Make sure failures (parse errors,
  HTTP/robots blocks, zero-result runs) are logged at warn/error level and are
  visible — not swallowed or buried at info. Cross-check against the ScrapeRun
  observability data. (See memory `project-scraper-run-observability`.)
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

### Features / design (settled, unbuilt)

- **Genre alias: match-not-rewrite.** Stop the *semantic* rewrite at ingest so an
  event keeps its raw token (e.g. `Elektronik`); resolve the alias at *query
  time* so the `Electronic` filter still matches + highlights it via a
  `canonical_id` link. Keeps source data intact, dedupes the two
  subtree-expansion copies. Full spec: memory `project-alias-match-not-rewrite`.
  (Does **not** affect the scrape over-count — that cosmetic branch is fixed.)

### UI polish

- **Typographic hierarchy pass.** Every page *except the main events page* should
  use a correct, consistent heading hierarchy (`h1`–`h6`, no level skips, one
  `h1` per page). Audit + fix across the app, then **document the scale and rules
  in `/styleguide`** so it stays enforced.
- **Uniform spacing pass.** Establish and apply consistent vertical/section
  spacing across all pages and their sections (page padding, section gaps,
  field/stack rhythm). Codify the spacing scale + rules in `/styleguide` and
  apply via shared utilities/tokens (not per-page one-offs).
- **General mobile-first sweep** of the app — ongoing direction, not a discrete
  ticket. Enforce the visual invariants: what's clickable is unambiguous; one
  visual representation per element; green only ever means "interested" (heart =
  saved shows). See memory `project-screenshot-design-review`.
- **Slow PWA start / splash screen** — cold start is sluggish; no splash handling
  yet. (See memory `project-pwa-install-affordance`.)
- **Dark PWA icon not wired into the manifest** — `icon-192-dark.png` exists but
  `manifest.json.erb` references only the single-theme icons. Minor.

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

- More scraper venues — backlog in `docs/scraper-backlog.md`.
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
