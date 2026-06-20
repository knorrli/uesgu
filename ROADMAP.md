# üsgu — Roadmap

> Working reference for what's built, what "complete" means, and the path there.
>
> üsgu is a **personal tool** — built until it feels useful, not an MVP to
> validate; friends are optional tag-alongs. **"Complete" = functional
> completeness first, then a UI polish pass.** Both are required, in that order:
> we don't polish UI for a feature set that isn't settled.

## Where we are

**Live on `main`:**

- **Data ingestion** — venue scrapers (+ PETZI aggregator with non-destructive
  dedup), genre-tree taxonomy + normalization, location hierarchy
  (venue/city/canton), cancellation detection, discard rules, scrape-run admin
  with drop-to-zero abort alerting.
- **Browsing** — events feed (list + calendar views), What/Where/When filter on
  the genre tree + date presets, calendar with saved-show day markers,
  light/dark theme, de/en/fr, installable PWA.
- **Accounts** — invite-only signup, username/password, optional email, settings.
- **Saved filters** — save any What/Where/When filter (funnel control on the
  events page, fingerprint-deduped); the main page filter stays ephemeral URL
  state. Notification delivery is optional per filter (in-app inbox, web push,
  email via Resend), auto-named editor + "Test now". Generalises the old
  notification rules and absorbs the retired Interests/Favorites feature.
- **Saved shows** — single-event save, "My saved shows", ICS subscription feed,
  midday "your saved show is tonight" reminders.
- **Admin** — dashboard, users, invitations, scrape runs, genre-tree + location
  catalogues, per-event manual overrides, genre curation (unplaced) queue,
  discard rules.

## Taxonomy + saved-filters redesign — ✅ SHIPPED (2026-06-20)

Collapsed three overlapping systems into two. The hand-curated **Style** layer
and the flat genre list became one **genre tree** (`genres.parent_id`,
descendant-expanding filters); the **Interests/Favorites** feature and the
**notification rules** became one **saved filter** (notification optional). Spec
+ full phase history: `docs/taxonomy-and-saved-filters-redesign.md`. Removed:
the Style model + styles taggings, the favorites page, `User#style_list` /
`location_list`, `track_favorites`. Deploy was a drop-and-recreate
(`bin/rails taxonomy:reset` in the Render shell + re-scrape); the curated tree
seed lives in `db/genres.yml`.

## Definition of "functionally complete" — ✅ REACHED

The bounded set where the tool serves daily use. All three pieces shipped to
`main`; functional completeness is met. Remaining work is the UI polish pass.

1. **Notifications close-out** — ✅ done (punch list §1).
2. **Per-event saving** — ✅ done (single-show save + "My saved shows", §2).
3. **Email third-party disclaimer** — ✅ done (§3).

## Punch list (ordered toward functional completeness)

### §1 — Notifications close-out (from the code review) — ✅ DONE (commit `132390a`)

- [x] **Wire the scheduler** — `notify-due` Render cron (`*/15`) runs `saved_filters:tick`
      (`lib/tasks/saved_filters.rake`; renamed from the old `notification_rules:tick`).
- [x] **Retire the legacy digest system** — dropped `notification_frequency` +
      `last_notified_at`, `Notification.generate_for`, `WebPushNotifier`,
      `GenerateNotificationsJob`, and the frequency selectors (signup/settings/admin).
      Rules are the sole notification mechanism.
- [x] **Drop the "only my favorites" toggle** on the digest page (rule defines relevance).
- [x] **Firehose guard** — a `track_favorites` rule with no current favorites matches nothing.
- [x] **Cadence/window clash → solved structurally:** a what's-on rule's cadence is
      *derived* from its window (`WINDOW_RHYTHM`: weekend/week→weekly, month→monthly,
      today→daily), so it fires exactly once per window — no over-/under-notification,
      no event-dedup needed. The form hides the cadence picker for windowed rules.

### §2 — Per-event saving — ✅ DONE (commit `32eb6e0`)

- [x] Save / unsave a single event — `EventSave` join + bookmark toggle on every
      event (list / calendar / digest) for logged-in users.
- [x] "My saved shows" view (`/saved_events`, upcoming saved events) + nav link.

### §3 — Email third-party disclaimer — ✅ DONE (already shipped `e516a2a`)

- [x] Inline, opt-in `settings.email_third_party` disclosure (names Resend) above
      the Settings email field — the only end-user email-entry point. de/en/fr.
      The digest email's "Manage rules" footer link is the paired opt-out.

### §4 — Deploy — ✅ DONE

- [x] Merged `notification-rules` → `main`, pushed (auto-deploys to Render).

## After functional: UI polish pass (required for "complete")

> **Direction (2026-06-16):** this is a *systemic* pass, not value tweaks. Pass-1
> on `ui-design-pass` fixed contrast/borders/calendar-width but read as
> "checklist-sync against an isolated styleguide." The real goal is enforcing a
> few **visual invariants** across the live app: (1) what's clickable is
> unambiguous; (2) every element has ONE visual representation (collapse the
> button/boolean/link variants); (3) **green only ever means "interested"**
> (decouple it from active-state + links; give "interested" its own non-green
> icon, reserve the heart for saved shows). Don't sand off identity (the
> "punched-out" plum-on-green button). See memory `project-screenshot-design-review`.
> The items below are symptoms of these, not an independent checklist.

Still open:

- **Saved-filter card visual hierarchy** — info chips vs. action buttons vs.
  links vs. destructive still read as similar squares (`saved_filters/index`).
  Detail + the green-left-border / Bearbeiten-link gripes in the session backlog
  below (2026-06-20).
- **General mobile-first pass** — sweep the app (`/favorites` is gone now).

Done since this list was written (verified in code 2026-06-20):

- Monthly day-of-month picker; 15-min notify-time `step="900"`; inbox-count N+1
  (now batched via `Notification.visible_event_counts`); duplicated `build_filter`
  (deduped — `SavedFiltersController` uses `filter_for`); dead `display_name`
  fallback (defensive, not dead — left); `rule_about` passthrough (removed);
  mailer event re-query (intentional, `includes` guards N+1); raw `event.url`
  href (validated via `digest_event_href`); DST off-by-one (`at_time` uses
  `Time.zone.local`); per-user email locale (`I18n.with_locale`). The
  favorites-OR query is moot (favorites removed).

## Session backlog — captured 2026-06-20 (post-taxonomy-followups walkthrough)

Findings from a live click-through of the shipped redesign. Unverified in code
unless noted — a fresh session should confirm specifics before acting. Roughly
ordered bugs-first, then UX, then polish.

### Bugs / correctness

- **What-filter freetext leaks onto Apply.** Apply unconditionally promotes the
  search-box text to a freetext term — even when that text was only used to
  *locate* a genre the user then ticked. Repro: type `ber`, tick **Chamber Pop**,
  Apply → filter ends up with both `Chamber Pop` (intended) **and** `ber`
  (stray). This has already polluted real saved filters (e.g. one titled
  "hop · Neue Events" — `hop` is a truncated **Hip Hop** search).
  - *Fix opt 1 (preferred):* on Apply, promote leftover freetext only if **no
    checkbox was toggled during the current open session**. Must be
    session-scoped — genres already applied before opening the filter must NOT
    suppress a genuinely-typed freetext term.
  - *Fix opt 2 (fallback):* keep the "Tippe, um nach allem zu suchen / Suchen
    nach „…"" prompt row as the **explicit** trigger to add freetext; never
    auto-add on Apply.
  - **Couples with the desktop-row item below** — opt 1 lets us hide the prompt
    row; opt 2 makes it load-bearing. Decide this first.
- **Filter chip render jumps content down** (regression after the redesign
  refactor). On the main events page, rendering the active-filter chip pushes the
  results list downward. Reserve the space / fix layout shift.
- **Some scrapers always report event-data updates.** ✅ **FIXED** (cause found
  via the prod-log diagnostic). The per-run "updated" counts were inflated by a
  false-positive diff: `Event#genre_list=` runs AATO's setter with the *raw*
  scraped tokens before canonicalising, so AATO flags the virtual
  `genre_list`/`location_list` dirty whenever the raw spelling differs from the
  stored canonical one (mostly cosmetic titleization, e.g. `"indie rock"` →
  stored `"Indie Rock"`) — a no-op that persists nothing. `Scrapers::Agent` now
  decides updated-vs-unchanged from what actually persisted (`saved_changes` real
  columns + a genre/location tag-set snapshot), ignoring that virtual dirty flag.
  Cosmetic normalization stays at ingest; only the miscount is gone.
- **Deleted event referenced by a notification.** Find out what happens when a
  notification links to an event that's since been deleted; degrade gracefully
  (e.g. "no longer available") instead of a broken/blank link. **Constraint:**
  only if it needs **no schema change**.

### Notifications / filters UX

- **Push checkbox must check push is actually set up.** In the filter
  Benachrichtigungen section, "Push auf meine Geräte" should verify push is
  enabled (per device/user); if not, mirror the email-checkbox pattern — show a
  message + link to settings rather than silently accepting. **Decision:** do
  NOT auto-trigger the browser enable-push flow from the checkbox; keep enabling
  push a deliberate, separate user action.
- **"Remind me about upcoming events" is in the wrong place** (currently on
  Settings). Either move it into the Notifications section, or make it
  per-filter — goal is *all notification user-choices in one place*, leaving
  Settings for setup/config only.
- **Detect & highlight "date changed / new date" events**, like the existing
  cancelled-event treatment, if a date change is detectable during scraping.

### Copy

- **Full copy pass over all UI text** (DE/FR/EN). Make every string cool and
  friendly, not business-y; strip technical jargon — nobody knows what a
  "funnel" is. Respect the established voice (informal, `tu` in French).

### UI polish

- **Hide the redundant prompt row on desktop** — the "Tippe, um nach allem zu
  suchen" first row of the What dropdown duplicates the search-input placeholder
  directly above it. **Contingent on the freetext bug above** (see opt 1 vs 2).
- **Sticky list-view date headers.** In list view (not the calendar day panel),
  pin each date header to the top while scrolling its group (`position: sticky` —
  still the right tool). Must keep the live-updating `♥saved ★interest` counts.
- **Merkliste icon → heart, not bookmark.** Switch the saved-shows toggle glyph.
  ⚠️ Do a quick save-vs-interest **icon audit** first — heart/green already carry
  meaning elsewhere (date headers render `♥` for saved; green = follows/state).
  Reconcile the whole system in one pass, don't flip just this spot. (Relates to
  the green-only-means-interested invariant in the UI-polish direction above.)
- **Admin gear icons in the genre row** (admin-only) are vertically misaligned
  and sit awkwardly *outside* the now-outlined genre tags. Consider a "button
  add-on" (a second segment of the tag button, no gap). Keep it cheap — admin
  only.
- **"N gelesene anzeigen" (show read notifications) link** on the inbox empty
  state has no click affordance and reads as plain grey body text — restyle to a
  styleguide-compliant link/button.
- **Saved-filters (Regeln) index cards** (`saved_filters/index`): (1) the
  fieldset/box container is a UI element used nowhere else — reconsider; (2) the
  green left border has no apparent meaning — give it purpose or drop it; (3) the
  "Bearbeiten" link clashes with the action buttons — the link-vs-button
  distinction won't read to users; reconcile even if it bends the styleguide
  rule. (Overlaps the "Saved-filter card visual hierarchy" item above.)
- **Edit-filter page** (`saved_filters/edit`): (1) add **back navigation**;
  (2) separate the **Filter** and **Benachrichtigungen** sections — they run
  together and the bold section headers read as form labels; add spacing/divider
  and consider codifying **vertical-spacing rules** in `/styleguide`; (3) the
  "Wann" select renders its value in **bold** unlike other inputs — match the
  regular input font weight.

## v2 / nice-to-have (explicitly later)

- Calendar export (ICS) of saved events + "your saved show is tonight" reminders
  are **DONE** (shipped 2026-06-16) — kept here only as a pointer.
- Session "Update the filter I just applied" soft-pointer (redesign decision 8).
- `featured`/`main_genre` flag + subtree-count browse ranking (redesign decision 6).
- **Genre alias: match-not-rewrite** (settled design, not built — full spec in the
  `project-alias-match-not-rewrite` memory note). Stop the *semantic* rewrite at
  ingest (`Genre.canonicalize_names` no longer substitutes an alias's canonical, so
  an event keeps its raw token e.g. `Elektronik`); resolve the alias at *query
  time* instead, so the genre filter for `Electronic` still matches + highlights it
  via a `canonical_id` link. Keeps source data intact (the Eventfrog §17(5) win) and
  dedupes the two subtree-expansion copies. Cosmetic fingerprint/display
  normalization stays. NB: this does **not** affect the scrape over-count above —
  that was the cosmetic branch, already fixed.

## Out of scope (not "incomplete")

- More scraper venues (backlog in `docs/scraper-backlog.md`).
- Vanished-event sweep / ratio alerting (declined as over-engineering).
- Password reset (no recovery flow by design).
- Scraper drop-to-zero alerting is **built** (exit-code abort → Render cron email).
