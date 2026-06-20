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

### Bugs

- **Schueuer scraper out-of-range.** `schueuer.rb` still `raise`s on an
  unparseable date, halting the scrape. Make it warn/skip the bad row instead.
  (See memory `project-schueuer-scraper-out-of-range`.)

### Features / design (settled, unbuilt)

- **Genre alias: match-not-rewrite.** Stop the *semantic* rewrite at ingest so an
  event keeps its raw token (e.g. `Elektronik`); resolve the alias at *query
  time* so the `Electronic` filter still matches + highlights it via a
  `canonical_id` link. Keeps source data intact, dedupes the two
  subtree-expansion copies. Full spec: memory `project-alias-match-not-rewrite`.
  (Does **not** affect the scrape over-count — that cosmetic branch is fixed.)

### UI polish

- **General mobile-first sweep** of the app — ongoing direction, not a discrete
  ticket. Enforce the visual invariants: what's clickable is unambiguous; one
  visual representation per element; green only ever means "interested" (heart =
  saved shows). See memory `project-screenshot-design-review`.
- **Slow PWA start / splash screen** — cold start is sluggish; no splash handling
  yet. (See memory `project-pwa-install-affordance`.)
- **Dark PWA icon not wired into the manifest** — `icon-192-dark.png` exists but
  `manifest.json.erb` references only the single-theme icons. Minor.

### Maybe-later (explicitly deferred)

- Reschedule **state-change-back** detection — core reschedule marking ships;
  detecting "was rescheduled, now back to the original date" doesn't.
- Session "Update the filter I just applied" soft-pointer.
- `featured`/`main_genre` flag + subtree-count browse ranking.

## Out of scope (not "incomplete")

- More scraper venues — backlog in `docs/scraper-backlog.md`.
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
