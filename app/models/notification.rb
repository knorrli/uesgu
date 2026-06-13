# A per-user digest produced when a NotificationRule fires: it snapshots the
# exact events it matched into event_ids, and title holds a frozen label so the
# inbox reads well even if the rule is later renamed or deleted. period_start/
# period_end record the coverage span for display.
#
# (Pre-existing window-based digests from the retired frequency system have no
# event_ids; their events are still recomputed from the created_at window so old
# inbox entries keep rendering.)
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :notification_rule, optional: true

  scope :unread, -> { where(read_at: nil) }
  scope :ordered, -> { order(period_end: :desc) }

  def rule_based?
    notification_rule_id.present? || event_ids.present?
  end

  # The events in this digest, narrowed to what's *currently* visible (an event
  # hidden after the fact drops out). Rule-based digests read their snapshot;
  # legacy window digests recompute from the created_at window.
  def events
    relation =
      if rule_based?
        Event.visible.where(id: event_ids)
      else
        Event.visible.where(created_at: period_start...period_end)
      end
    relation.order(start_date: :asc)
  end

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.current) unless read?
  end
end
