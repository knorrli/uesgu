namespace :saved_filters do
  # The per-user-due delivery sweep. Meant to run frequently (a Render cron every
  # ~15 min, like scrape-all but tighter) so each rule fires within ~a quarter
  # hour of its chosen time-of-day. Idempotent: a rule whose scheduled moment
  # hasn't passed (or already fired) is skipped, so re-running is harmless.
  #
  # Wired into render.yaml as the `notify-due` cron (schedule "*/15 * * * *").
  # Also runs the saved-show reminder sweep (EventReminder) — both share this one
  # cron since both are idempotent via their own per-fire guards.
  desc 'Fire all due saved filters + saved-show reminders (run frequently from cron)'
  task tick: :environment do
    now = Time.current
    sent = SavedFilter.run_due!(now)
    # Saved-show reminders ride the same quarter-hourly sweep (both are idempotent
    # via their own per-fire guards), so no second cron is needed.
    reminders = EventReminder.run_due!(now)
    line = "[saved_filters] tick #{now.iso8601}: #{sent.size} digest(s), #{reminders.size} reminder(s) sent"
    Rails.logger.info(line)
    puts line
  end
end
