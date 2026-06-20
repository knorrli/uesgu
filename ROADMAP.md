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
- [x] **Wire the scheduler** — `notify-due` Render cron (`*/15`) runs `notification_rules:tick`.
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
- **`.button-ghost` alias** — a documented no-op alias (controls.css comment +
  styleguide). Dropping it is a 13-file app-wide sweep, provably visually
  identical. NOTE: the calendar-feed buttons in `settings/show` use a *standalone*
  `button-ghost` (no `button-small`) with no matching CSS rule → they render
  unstyled. Real pre-existing bug; decide the fix (likely `button-small
  button-ghost`) when sweeping.
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

## v2 / nice-to-have (explicitly later)
- Calendar export (ICS) of saved events + "your saved show is tonight" reminders
  are **DONE** (shipped 2026-06-16) — kept here only as a pointer.
- Session "Update the filter I just applied" soft-pointer (redesign decision 8).
- `featured`/`main_genre` flag + subtree-count browse ranking (redesign decision 6).

## Out of scope (not "incomplete")
- More scraper venues (backlog in `docs/scraper-backlog.md`).
- Vanished-event sweep / ratio alerting (declined as over-engineering).
- Password reset (no recovery flow by design).
- Scraper drop-to-zero alerting is **built** (exit-code abort → Render cron email).
