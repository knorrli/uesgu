class VenueLead < ApplicationRecord
  validates :venue, :source, presence: true

  scope :by_demand, -> { order(event_count: :desc, venue: :asc) }

  def self.refresh!(source:, leads:)
    transaction do
      where(source: source).delete_all
      leads.each { |attrs| create!(attrs.merge(source: source)) }
    end
  end
end
