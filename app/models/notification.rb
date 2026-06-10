# A sealed per-user digest covering events added to the global list during
# [period_start, period_end). The window is fixed at creation, so a digest stays
# re-viewable forever; new events fall into the next period.
class Notification < ApplicationRecord
  belongs_to :user

  scope :unread, -> { where(read_at: nil) }
  scope :ordered, -> { order(period_end: :desc) }

  # Events added to the global list during this digest's window.
  def events
    Event.visible.where(created_at: period_start...period_end).order(start_date: :asc)
  end

  # Events in the window narrowed to the user's favorite locations OR styles.
  # Falls back to all events when the user has no favorites.
  def relevant_events
    locations = user.location_list
    styles = user.style_list
    return events if locations.empty? && styles.empty?

    events.ransack(
      g: [{ locations_name_in: locations.presence, styles_name_in: styles.presence, m: Ransack::Constants::OR }]
    ).result(distinct: true)
  end

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.current) unless read?
  end

  # Seal every fully-elapsed period since the user was last notified, creating a
  # digest for each window that actually has new events. Advances last_notified_at.
  # Idempotent given the same clock; safe to call lazily on page load or from a job.
  def self.generate_for(user, now: Time.current)
    interval = user.notification_interval

    # "never": notifications off. Keep the cursor current so that if the user
    # later re-enables them they start fresh, rather than receiving a backlog.
    if interval.nil?
      user.update_column(:last_notified_at, now)
      return []
    end

    created = []

    # Lock the user row so two concurrent calls (double-click, prefetch + click,
    # two tabs) can't both pass the cursor check and create duplicate digests for
    # the same window — the second waits, then sees the advanced last_notified_at.
    user.with_lock do
      cursor = user.last_notified_at || user.created_at

      while cursor + interval <= now
        window_end = cursor + interval
        if Event.visible.where(created_at: cursor...window_end).exists?
          created << user.notifications.create!(period_start: cursor, period_end: window_end)
        end
        cursor = window_end
      end

      user.update_column(:last_notified_at, cursor) if cursor != (user.last_notified_at || user.created_at)
    end

    created
  end
end
