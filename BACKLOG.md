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
- **Genuine field gaps are now declared in-code (2026-06-22).** Sources that
  structurally don't expose a coverage field are recorded with
  `field_gaps subtitle: :no_field` / `genres: :no_field` on the scraper class
  (`Scrapers::Agent.field_gaps`); the coverage matrix renders those cells as a
  muted **n/a** (reason on hover) instead of red, so a settled "does this source
  expose X?" question isn't re-asked. Honesty guard: if a declared-absent field
  ever ships real coverage, the live % wins over the declaration. Reasons:
  `no_field` (no such field at the source) and `dormant` (field exists in the
  feed but the source never fills it — e.g. Rote Fabrik's always-empty `tags`).
  Declared so far — genres (no_field): bad_bonn, boeroem, dampfzentrale,
  helsinki, kairo, kaserne, kofmehl, neubad, nouveau_monde, saegegasse,
  sous_soul, turnhalle, volkshaus; genres (dormant): rote_fabrik; subtitle
  (no_field): bar59, dynamo, kairo, kaserne, petzi, roessli, turnhalle,
  volkshaus. To extend: add `field_gaps …` to the scraper, never a hand-kept
  doc. NB: a source with no genre field but incidental coverage from PETZI
  merges / admin pins (kofmehl, neubad, helsinki) still shows that live % per
  the reality-wins rule — the declaration is the in-code capability record, it
  doesn't blank the cell.
- **Real extractor defects to chase (group B — source HAS the data, we drop it).**
  Surfaced by the 2026-06-22 fixture audit; these are NOT gaps, they're fixes:
  - ~~**muehle_hunziken subtitle (0%).**~~ DONE (2026-06-22) — pulls the list-row
    `text-sm md:text-xl` line (support act / tour note); fixture 0% → 41%.
  - ~~**rote_fabrik genres (0%).**~~ RESOLVED (2026-06-22) — not a defect: the feed
    ships `tags` but leaves it empty, and `categories` is only Konzert/Party type
    tags. Declared a `dormant` field gap (extractor stays wired; reality-wins
    surfaces the % if they ever populate `tags`).
  - ~~**docks (genres 41%).**~~ DONE (2026-06-22) — the `.artist-info` spans mixed
    a 2-letter ISO origin code (US/CH/AU) with the genre word under one class;
    now drop the bare codes so they stop minting bogus `Us`/`Ch`/`Au` genres.
    (Subtitle 32% left as-is: the `.event-subtitle` support-act extractor works;
    most concerts just list no support — honest-low, not a defect.)
  - ~~**suedpol subtitle (0%).**~~ NO ACTION (2026-06-22) — not a bug: the ACF
    `subtitle` AND `support` fields are both genuinely almost always empty
    (2/21 in the fixture) and the extractor works. Genres ~50% is likewise just
    sparse source tagging (no other genre source). Honest-low, nothing to fix.
  - ~~**kofmehl genres (29%)**, **neubad (33%, 1 distinct)**, **helsinki (19%)**.~~
    DONE (2026-06-22) — all three sites expose no music-genre field (only event
    *types* where any: Konzert/Klubnacht); the coverage is incidental PETZI-merge
    leakage. Declared `genres: :no_field` on each.
  - ~~**petzi subtitle (0%).**~~ DONE (2026-06-22) — no structured subtitle/support
    field (title + a free-text description blurb only). Declared `subtitle:
    :no_field`.
- **Curation follow-up (not a scraper task): retire the bogus Docks genres.** The
  Docks fix stops *minting* origin codes, and a re-scrape drops them from live
  events, but the already-minted `Us` / `Ch` / `Au` (and any other 2-letter)
  Genre rows linger in the taxonomy until blocked/merged in the admin genre
  curation queue.
- **Nouveau Monde: lineup jammed onto the title.** Event #285 title is stored as
  `Fête de la Musique : Brunch musical, La Gustav + Cold TouchLa GustavCold Touch`
  — the parser appends the artist names to the title with no separator (the
  subtitle already carries `La Gustav (ch), Cold Touch (ch)` correctly). Surfaced
  by the mobile sweep as a broken-looking title; root cause is the Nouveau Monde
  scraper's title extraction, not the view.

- **Run the Rote Fabrik URL backfill on prod.** The scraper fix + the
  `scrapers:rote_fabrik:fix_urls` backfill have shipped; the 15 local rows are
  healed. Prod still has the dead `kalender.rotefabrik.ch` URLs — run
  `bin/rails scrapers:rote_fabrik:fix_urls` on the Render shell **before the next
  nightly sweep** so the events heal in place instead of the sweep creating fresh
  rows and orphaning the old ones. (`DRY_RUN=1` to preview first.)

### UI polish

- **General mobile-first sweep** of the app — ongoing direction, not a discrete
  ticket. Enforce the visual invariants: what's clickable is unambiguous; one
  visual representation per element; green only ever means "interested" (heart =
  saved shows). See memory `project-screenshot-design-review`.
- **Slow PWA start / splash screen** — cold start is sluggish; no splash handling
  yet. (See memory `project-pwa-install-affordance`.)

### Maybe-later (explicitly deferred)

- Session "Update the filter I just applied" soft-pointer.
- `featured`/`main_genre` flag + subtree-count browse ranking.

## Out of scope (not "incomplete")

- More scraper venues — candidate/evaluated venues live in `config/venue_ledger.yml` (defer/reject rows); discovery via `docs/discovery-design.md`.
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
