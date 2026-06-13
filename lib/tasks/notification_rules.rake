namespace :notification_rules do
  # The per-user-due delivery sweep. Meant to run frequently (a Render cron every
  # ~15 min, like scrape-all but tighter) so each rule fires within ~a quarter
  # hour of its chosen time-of-day. Idempotent: a rule whose scheduled moment
  # hasn't passed (or already fired) is skipped, so re-running is harmless.
  #
  # NOT YET WIRED INTO render.yaml — this is the experimental branch. To go live,
  # add a cron service mirroring scrape-all with `schedule: "*/15 * * * *"` and
  # `startCommand: bin/rails notification_rules:tick`.
  desc "Fire all due notification rules (run frequently from cron)"
  task tick: :environment do
    now = Time.current
    sent = NotificationRule.run_due!(now)
    Rails.logger.info("[notification_rules] tick #{now.iso8601}: #{sent.size} digest(s) sent")
    puts "[notification_rules] tick #{now.iso8601}: #{sent.size} digest(s) sent"
  end
end
