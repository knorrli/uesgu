# Notification rules — experimental build

Branch: `notification-rules` (not pushed, not deployed).

A notification rule is **a saved landing-page filter + a schedule**. You filter
the events page as usual, hit **"Notify me"**, and pick how often / when / on
which channel. No separate builder, no jargon.

## The model (what the user never has to think about)

- **What it's about** = whatever your filter is (styles / locations / search /
  date). Matched exactly like the landing page.
- **Newly-added vs. what's-on** = *inferred*, not chosen:
  - filter has a **relative date** (this weekend, next week…) → **"What's on"**:
    events in that window, re-resolved each time it fires.
  - filter has **no date** → **"New"**: events newly added since the rule last
    fired (future-dated only).
- **Channel** = in-app inbox always, + push and/or email per rule.
- **Favorites** = frozen by default (the tags you saved). If your filter exactly
  matches your favorites, an optional **"Keep in sync with my favorites"**
  checkbox makes it live (re-resolved at send time). Shown only when relevant.
- An **empty filter is disallowed** (no "all new events" firehose) — the
  "Notify me" button is hidden when no filter is active.

## Run it

```sh
git checkout notification-rules
bin/rails server
```

Log in, filter the events page (e.g. a style, or "this weekend"), and the
**🔔 Notify me** button appears next to "My favorites". It opens a small page:
filter preview + how-often / at-what-time / channels (+ the sync checkbox when
your filter is your favorites). Saved alerts live under the account menu →
**Mitteilungs-Regeln** (a read-only list: pause / delete / "open filter" /
**Test now**).

### Email

- **Preview without sending:** http://localhost:3000/rails/mailers/notification_mailer/digest
- **Real one to yourself:** set your address in Settings, make an alert with
  "E-Mail an mich", then **Test now**. Arrives from `üsgu <noreply@uesgu.ch>`.

### Push

Enable push for this device in Settings, then any alert with push on sends a
short blurb deep-linking to the in-app page. (iPhone needs the PWA on the home
screen first.)

## The scheduler (not yet deployed)

```sh
bin/rails notification_rules:tick   # fires every alert that's due right now
```

Not wired into `render.yaml` yet. Go-live = a cron service mirroring
`scrape-all` with `schedule: "*/15 * * * *"` and
`startCommand: bin/rails notification_rules:tick`.

## Where things live

- `app/models/notification_rule.rb` — saved filter + schedule; `due?`,
  `matched_events` (added vs happening inferred), `fire!`, `run_due!`
- `app/controllers/notification_rules_controller.rb` — `new`/`create` (from the
  filter), read-only `index`, `fire`/`toggle`/`destroy`
- `app/views/events/_notify_button.html.erb` — the landing-page button
- `app/views/notification_rules/{new,index}.html.erb` — schedule form / "My alerts"
- `app/javascript/controllers/rule_form_controller.js` — weekday/monthday show-hide
- `app/services/notification_push.rb`, `app/mailers/notification_mailer.rb` +
  `config/initializers/mail.rb` (Resend SMTP, inert without a key)
- `lib/tasks/notification_rules.rake` — the `tick` sweep
- Tests: `test/models/notification_rule_test.rb`,
  `test/integration/notification_rules_test.rb`,
  `test/mailers/notification_mailer_test.rb`

## Rough edges / decisions

- Filter is **frozen** at save (except the live-favorites opt-in). "Edit" reopens
  the filter on the events page — change it and save a new alert.
- The new-alert page is a **dedicated page**, not an inline popover, to keep the
  landing page light. Easy to make inline later if you prefer fewer clicks.
- Biweekly parity (which fortnight) is approximate.
- de/en/fr strings present.

Full suite: **295 runs, 0 failures.**
