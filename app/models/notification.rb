class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :saved_filter, optional: true

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :ordered, -> { order(created_at: :desc) }

  def rule_based?
    saved_filter_id.present? || event_ids.present?
  end

  def self.visible_event_counts(notifications)
    rule_based, legacy = notifications.partition(&:rule_based?)
    visible_ids = Event.visible.where(id: rule_based.flat_map(&:event_ids).uniq).pluck(:id).to_set

    counts = {}
    rule_based.each { |n| counts[n.id] = n.event_ids.count { |id| visible_ids.include?(id) } }
    legacy.each { |n| counts[n.id] = n.events.count }
    counts
  end

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
