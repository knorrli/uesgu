namespace :notifications do
  # Replayable in-app notifications demo.
  #
  # It never deletes or rescrapes real events: digests are derived from existing
  # events by `created_at`, so all the demo needs is a user whose `last_notified_at`
  # is in the past. For a clean, predictable "Only my favorites" view it also seeds
  # a handful of clearly-marked demo events (url host `demo.uesgu.local`) tagged with
  # demo-only favorites, then cleans up exactly those rows on the next run.
  #
  # Re-run any time to replay from scratch:  bin/rails notifications:demo
  desc "Set up / reset the replayable in-app notifications demo (real events untouched)"
  task demo: :environment do
    URL_PREFIX = "https://demo.uesgu.local/".freeze
    USERNAME = "demo".freeze
    PASSWORD = "demodemo".freeze
    FAV_LOCATION = "Demo Hall".freeze
    FAV_STYLE = "DemoBeat".freeze

    now = Time.current

    user = User.find_or_initialize_by(username: USERNAME)
    user.password = PASSWORD if user.new_record?
    user.notification_frequency = "weekly"
    user.save!
    user.location_list = [FAV_LOCATION]
    user.style_list = [FAV_STYLE]
    user.save!

    # Reset ONLY demo-owned state.
    user.notifications.delete_all
    Event.where("url LIKE ?", "#{URL_PREFIX}%").destroy_all

    # Seed two demo events in each of the last three weekly windows. Created mid-week
    # so they fall cleanly inside one period; start_date in the near future.
    [18, 11, 4].each_with_index do |days_ago, window|
      2.times do |n|
        i = window * 2 + n
        event = Event.create!(
          title: "Demo Event #{i + 1}",
          subtitle: "Seeded by notifications:demo",
          url: "#{URL_PREFIX}#{i}",
          start_date: (now + (7 - window).days).to_date
        )
        # First event of each window matches the demo favorites, the second does not,
        # so the "Only my favorites" toggle is visibly meaningful.
        event.location_list = n.zero? ? FAV_LOCATION : "Other Venue"
        event.style_list = n.zero? ? FAV_STYLE : "Pop"
        event.save!
        event.update_column(:created_at, now - days_ago.days - n.hours)
      end
    end

    user.update_column(:last_notified_at, now - 21.days)
    notifications = Notification.generate_for(user, now: now)

    puts "\nNotifications demo ready."
    puts "  Log in as:  #{USERNAME} / #{PASSWORD}"
    puts "  Then open:  /notifications"
    puts "  Generated #{notifications.size} digest(s):"
    notifications.each do |n|
      puts "    #{n.period_start.to_date}..#{n.period_end.to_date}  —  #{n.events.count} new (#{n.relevant_events.count} match favorites)"
    end
    puts ""
  end

  desc "Remove all notifications:demo data (demo user + seeded events)"
  task demo_clear: :environment do
    Event.where("url LIKE ?", "https://demo.uesgu.local/%").destroy_all
    User.where(username: "demo").destroy_all
    puts "Demo data removed."
  end
end
