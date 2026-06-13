# Notification rules — experimental build

Branch: `notification-rules` (not pushed, not deployed). Built overnight 2026-06-13.

This turns "notifications" into a **list of rules**, each one a funnel:

> **WHEN** (cadence + time-of-day) · **WHICH EVENTS** (newly added / happening in a window) · **WHICH FILTER** (all / favorites / custom) · **CHANNEL** (in-app always, + push and/or email per rule)

Every one of your seven scenarios maps onto these knobs. All three delivery
channels are real — **email is live via Resend** (your key + verified domain).

## Run it

```sh
git checkout notification-rules
bin/rails server
```

Log in, open the account menu (top right) → **Mitteilungs-Regeln**. You'll see
your rules (none yet) and the builder below.

## What to try

1. **Build a rule** with the inline form. The fields show/hide based on your
   choices (weekday only for weekly, window only for "happening", the custom
   filter only for "custom scope").
2. **Hit "Jetzt testen" (Test now)** on a saved rule — it fires immediately on
   the real channels, so you don't wait for the schedule. Then check the
   in-app inbox (**Mitteilungen**) to see the digest it produced.
3. Map your scenarios, e.g.:
   - *daily new events at 17:30* → daily · 17:30 · newly added · all (or favorites)
   - *every Friday, what's on in Bern this weekend* → weekly · Fri · happening · this_weekend · custom (locations: `Bern`)
   - *every Sunday, rock at Dachstock or Rössli next week* → weekly · Sun · happening · next_week · custom (styles: `Rock`, locations: `Dachstock, Rössli`)

### Email

- **Preview without sending:** http://localhost:3000/rails/mailers/notification_mailer/digest
  — the self-contained digest (events inline) + a button to the in-app page.
- **Send a real one to yourself:** set your address in **Settings → E-Mail**,
  create a rule with **"E-Mail an mich"** checked, then **Test now**. It will
  arrive from `üsgu <noreply@uesgu.ch>`.

### Push

Enable push for this device in **Settings** (existing flow), then any rule with
**"Push auf meine Geräte"** sends a short blurb that deep-links to the in-app
page. (On iPhone, push needs the PWA added to the home screen first.)

## The scheduler (not yet deployed)

Rules fire automatically via a per-user-due sweep. The entry point exists:

```sh
bin/rails notification_rules:tick   # fires every rule that's due right now
```

It's **not wired into `render.yaml` yet** (this is the experiment). To go live,
add a cron service mirroring `scrape-all` with `schedule: "*/15 * * * *"` and
`startCommand: bin/rails notification_rules:tick`. A 15-min cadence means a
17:30 rule fires by ~17:45 — invisible for a digest.

## Honest list of rough edges / decisions

- **Custom filter = plain text inputs** (comma-separated). Names must match the
  style/location spelling used on the site. Could later reuse the same
  comboboxes as the main filter — left simple for the prototype.
- **Biweekly parity** (which fortnight) is approximate, anchored to the rule's
  creation date.
- The **old single "frequency" setting** in Settings still exists and works
  (legacy digest). Rules supersede it; I left it untouched rather than ripping
  it out mid-experiment.
- **"What's on tonight" as its own thing** isn't separate — it's just a
  `happening` rule with a `today`/`this_weekend` window.
- de/en/fr strings all present (de/en are primary).
- Visual styling + the show/hide form JS are best eyeballed — tests cover the
  server/logic, not pixels.

## Where things live

- `app/models/notification_rule.rb` — the rule: `due?`, `matched_events`, `fire!`, `run_due!`
- `app/controllers/notification_rules_controller.rb` + `app/views/notification_rules/index.html.erb`
- `app/javascript/controllers/rule_form_controller.js` — conditional fields
- `app/helpers/notification_rules_helper.rb` — options + `rule_summary`
- `app/services/notification_push.rb` — rule-aware push
- `app/mailers/notification_mailer.rb` + `app/views/notification_mailer/*` + `config/initializers/mail.rb` (Resend SMTP, inert without a key)
- `app/models/notification.rb` — now renders from a rule's event snapshot
- `lib/tasks/notification_rules.rake` — the `tick` sweep
- Tests: `test/models/notification_rule_test.rb`, `test/integration/notification_rules_test.rb`, `test/mailers/notification_mailer_test.rb`

Full suite: **293 runs, 0 failures.**
