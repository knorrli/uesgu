# üsgu — Roadmap

> Working reference for what's built, what "complete" means, and the path there.
>
> üsgu is a **personal tool** — built until it feels useful, not an MVP to
> validate; friends are optional tag-alongs. **"Complete" = functional
> completeness first, then a UI polish pass.** Both are required, in that order:
> we don't polish UI for a feature set that isn't settled.

## Where we are

**Live on `main`:**
- **Data ingestion** — venue scrapers, genre→style taxonomy + normalization,
  location hierarchy (venue/city/canton), cancellation detection, scrape-run admin.
- **Browsing** — events feed (list + calendar views), What/Where/When filter +
  date presets, calendar with saved/interest day markers, light/dark theme,
  de/en/fr, installable PWA.
- **Accounts** — invite-only signup, username/password, optional email, settings.
- **Favorites** — follow locations + styles (inline hearts + `/favorites`),
  "My favorites" filter shortcut.
- **Admin** — dashboard, users, invitations, scrape runs, genre/style/location
  catalogues, per-event manual overrides, genre "tinder" queue, discard rules.
- **Saved shows** — single-event save, "My saved shows", ICS feed, midday reminders.
- **Notifications** — rule-based alerts (saved filter + schedule), in-app inbox,
  web push, email (Resend), auto-naming, "Test now".

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
- Notification-rules card visual hierarchy — info chips vs. action buttons vs.
  links vs. destructive currently all read as similar squares.
- Monthly day-of-month picker on the new-alert form.
- Constrain the notify-time input to 15-min steps (`step="900"`) — the `notify-due`
  cron ticks at :00/:15/:30/:45, so finer granularity implies precision we don't
  deliver (a rule fires at the first tick ≥ its time).
- General mobile-first pass (`/favorites` now reads fine on mobile — done; sweep
  the rest of the app).
- Review cleanup/efficiency: inbox-count N+1, duplicated `build_filter` across two
  controllers, duplicated favorites-OR query, dead `display_name` fallback,
  `rule_about` passthrough, mailer re-queries events `fire!` already loaded,
  `event.url` rendered raw into the email href.
- Lower-severity correctness from the review: DST off-by-one-hour on transition
  days; email *heading* can show a default-locale title to non-de users via cron.

## v2 / nice-to-have (explicitly later)
- **Calendar export (ICS)** of saved events.
- **In-app reminder notifications** for saved events ("your saved show is tonight").

## Out of scope (not "incomplete")
- More scraper venues, scraper health-alerting (drop-to-zero), password reset.
