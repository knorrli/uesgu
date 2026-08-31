class DiscardRule < ApplicationRecord
  has_many :discarded_events, class_name: "Event", foreign_key: :discarded_by_rule_id,
                              inverse_of: :discarded_by_rule, dependent: :nullify

  validates :pattern, presence: true, length: { minimum: 2 }

  scope :active, -> { where(active: true) }
  scope :by_recency, -> { order(created_at: :desc) }

  def matching_events
    needle = "%#{ActiveRecord::Base.sanitize_sql_like(pattern.to_s)}%"
    scope = Event.kept.where("events.title ILIKE :n OR events.description ILIKE :n", n: needle)
    scope = scope.tagged_with(scraper, on: :locations) if scraper.present?
    scope
  end

  def matches?(title:, description:, location:)
    return false if pattern.blank?
    return false if scraper.present? && scraper != location

    needle = pattern.downcase
    title.to_s.downcase.include?(needle) || description.to_s.downcase.include?(needle)
  end

  def self.reapply_all!
    Event.kept.where.not(discarded_by_rule_id: nil).update_all(discarded_by_rule_id: nil)
    active.by_recency.each do |rule|
      ids = rule.matching_events.where(discarded_by_rule_id: nil).pluck("events.id")
      Event.where(id: ids).update_all(discarded_by_rule_id: rule.id)
    end
  end

  def self.venue_options
    Scrapers::All.scrapers.values.map(&:location).uniq.sort
  end
end
