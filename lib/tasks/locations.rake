namespace :locations do
  desc "Reconcile stored location tags (on events and user favorites) with the " \
       "current scraper-derived hierarchy. Drops any location tag that no longer " \
       "belongs — e.g. an alias removed from a scraper's `locations` array, or a " \
       "retired venue. Safe to re-run (idempotent) and the natural cleanup step " \
       "whenever scraper location metadata changes."
  task reconcile: :environment do
    valid = Location.hierarchy
                    .flat_map { |canton, cities| [canton] + cities.keys + cities.values.flatten }
                    .to_set

    events_changed = 0
    Event.find_each do |event|
      kept = event.location_list & valid.to_a
      next if kept.sort == event.location_list.sort

      event.location_list = kept
      event.save!
      events_changed += 1
    end
    puts "Events reconciled: #{events_changed}"

    users_changed = 0
    User.find_each do |user|
      kept = user.location_list & valid.to_a
      next if kept.sort == user.location_list.sort

      dropped = user.location_list - kept
      user.location_list = kept
      user.save!
      users_changed += 1
      puts "  User ##{user.id}: dropped #{dropped.join(', ')}"
    end
    puts "Users reconciled: #{users_changed}"

    # Remove tag rows that, after the above, no longer tag anything.
    unused = ActsAsTaggableOn::Tag.left_joins(:taggings).where(taggings: { id: nil })
    names = unused.pluck(:name)
    ActsAsTaggableOn::Tag.where(id: unused.pluck(:id)).destroy_all
    puts "Unused tags removed (#{names.size}): #{names.join(', ')}" if names.any?
  end
end
