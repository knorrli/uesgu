namespace :saved_filters do
  desc "Fire all due saved filters + saved-show reminders (run frequently from cron)"
  task tick: :environment do
    now = Time.current
    sent = SavedFilter.run_due!(now)
    reminders = EventReminder.run_due!(now)
    line = "[saved_filters] tick #{now.iso8601}: #{sent.size} digest(s), #{reminders.size} reminder(s) sent"
    Rails.logger.info(line)
    puts line
  end
end
