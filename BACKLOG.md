# üsgu — Backlog

> Single source of truth for **what's left**. If an open item isn't here, it
> isn't tracked. Reconciled against code on 2026-06-21 (the old punch list and
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
- **Nouveau Monde: lineup jammed onto the title.** Event #285 title is stored as
  `Fête de la Musique : Brunch musical, La Gustav + Cold TouchLa GustavCold Touch`
  — the parser appends the artist names to the title with no separator (the
  subtitle already carries `La Gustav (ch), Cold Touch (ch)` correctly). Surfaced
  by the mobile sweep as a broken-looking title; root cause is the Nouveau Monde
  scraper's title extraction, not the view.

### UI polish

- **General mobile-first sweep** of the app — ongoing direction, not a discrete
  ticket. Enforce the visual invariants: what's clickable is unambiguous; one
  visual representation per element; green only ever means "interested" (heart =
  saved shows). See memory `project-screenshot-design-review`.
- **Slow PWA start / splash screen** — cold start is sluggish; no splash handling
  yet. (See memory `project-pwa-install-affordance`.)
- **Create filters directly on the saved-filters index.** Today the only way to
  make a filter is to build one on the feed and save it from there; the
  `/saved_filters` page just points back ("Filter the events on the home page,
  then save it"). Let users compose + save a filter straight from the index.
  (User feedback, 2026-06-20.)

### Maybe-later (explicitly deferred)

- Session "Update the filter I just applied" soft-pointer.
- `featured`/`main_genre` flag + subtree-count browse ranking.

## Out of scope (not "incomplete")

- More scraper venues — candidate/evaluated venues live in `config/venue_ledger.yml` (defer/reject rows); discovery via `docs/discovery-design.md`.
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
