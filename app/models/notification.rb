# A per-user digest produced when a SavedFilter fires: it snapshots the
# exact events it matched into event_ids, and title holds a frozen label so the
# inbox reads well even if the rule is later renamed or deleted. period_start/
# period_end record the coverage span for display.
#
# (Pre-existing window-based digests from the retired frequency system have no
# event_ids; their events are still recomputed from the created_at window so old
# inbox entries keep rendering.)
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :saved_filter, optional: true

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  # Newest received first. created_at — not period_end, which for "happening
  # soon" rules is the (future) end of the event window, not the arrival time.
  scope :ordered, -> { order(created_at: :desc) }

  def rule_based?
    saved_filter_id.present? || event_ids.present?
  end

  # Currently-visible event count for a batch of notifications without an N+1:
  # every rule-based snapshot's event_ids is checked for visibility in ONE query,
  # then counted in Ruby (an event hidden after the fact drops out, matching
  # #events). Legacy window digests (no event_ids) keep their own per-record
  # query — only the few pre-frequency-system rows take that path. Returns a hash
  # keyed by notification id.
  def self.visible_event_counts(notifications)
    rule_based, legacy = notifications.partition(&:rule_based?)
    visible_ids = Event.visible.where(id: rule_based.flat_map(&:event_ids).uniq).pluck(:id).to_set

    counts = {}
    rule_based.each { |n| counts[n.id] = n.event_ids.count { |id| visible_ids.include?(id) } }
    legacy.each { |n| counts[n.id] = n.events.count }
    counts
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
