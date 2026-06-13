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
  date presets, busyness calendar, light/dark theme, de/en/fr, installable PWA.
- **Accounts** — invite-only signup, username/password, optional email, settings.
- **Favorites** — follow locations + styles (inline hearts + `/favorites`),
  "My favorites" filter shortcut.
- **Admin** — dashboard, users, invitations, scrape runs, genre/style/location
  catalogues, per-event manual overrides, genre "tinder" queue.

**On the `notification-rules` branch (not deployed):**
- **Notifications** — rule-based alerts (a saved filter + a schedule), in-app
  inbox, web push, email (Resend), auto-naming, "Test now".

## Definition of "functionally complete"

The bounded set where the tool serves daily use. Three pieces remain; everything
else live today already counts.

1. **Notifications close-out** — finish the in-flight feature (punch list §1).
2. **Per-event saving** — save a single show + a "My saved shows" view. The other
   half of "a tool, not an aggregator" (today only venues/styles are followable).
3. **Email third-party disclaimer** — disclose the Resend hand-off at the
   email-entry point (privacy ethos), now that email sends for real.

## Punch list (ordered toward functional completeness)

### §1 — Notifications close-out (from the code review)
- [ ] **Wire the scheduler** — `notification_rules:tick` as a ~15-min Render cron
      (mirrors `scrape-all`). Without this, nothing fires automatically.
- [ ] **Retire / gate the legacy digest system** — `Notification.generate_for` +
      `notification_frequency` still run on every inbox visit, intermixing
      window-digests with rule digests. Rules supersede them — decide to remove.
- [ ] **Drop the "only my favorites" toggle** for rule-based digests — incoherent
      (the rule already defines relevance; re-narrowing by current favorites yields
      empty/wrong results).
- [ ] **Firehose guard** — a `track_favorites` rule whose user later unfollowed
      everything matches *all* future events; send nothing instead.
- [ ] **Daily "what's-on" behavior** — decide whether a happening-rule on a short
      cadence re-sends the same window's events each tick (dedup vs. accept).

### §2 — Per-event saving
- [ ] Save / unsave a single event (new primitive).
- [ ] "My saved shows" view.

### §3 — Email third-party disclaimer
- [ ] Inline, opt-in disclosure at the email-entry point.

### §4 — Deploy
- [ ] Optionally apply the review's pre-merge cleanups (below).
- [ ] Merge `notification-rules` → `main`, deploy, verify cron + push + email in prod.

## After functional: UI polish pass (required for "complete")
- Notification-rules card visual hierarchy — info chips vs. action buttons vs.
  links vs. destructive currently all read as similar squares.
- Monthly day-of-month picker on the new-alert form.
- General mobile-first pass (e.g. `/favorites` flagged as rough).
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
