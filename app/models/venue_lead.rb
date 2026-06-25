# A venue an aggregator surfaced that matches NO approved venue in the registry —
# a discovery LEAD for a human to review and, if wanted, approve (add a row to
# config/venues.yml). The closed-allowlist's "what am I NOT ingesting?" inbox.
#
# Recorded fresh each aggregator run, per source (refresh! = delete + reinsert), so
# a lead that's since been approved or aged out of the feed simply drops off. Each
# carries the count of upcoming events it would bring, for ranking the inbox.
#
# (Was VenuePlace, which fed the location taxonomy until the venue registry took
# that over — see PR #29 and docs/venue-registry-design.md.)
class VenueLead < ApplicationRecord
  validates :venue, :source, presence: true

  # Highest-demand leads first — the inbox ranking.
  scope :by_demand, -> { order(event_count: :desc, venue: :asc) }

  # Replace this source's leads with the current run's set (idempotent per run).
  # `leads` is an array of { venue:, city:, canton:, event_count: } hashes.
  def self.refresh!(source:, leads:)
    transaction do
      where(source: source).delete_all
      leads.each { |attrs| create!(attrs.merge(source: source)) }
    end
  end
end
