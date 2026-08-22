# A venue that matches NO approved venue in the registry — a discovery LEAD for a
# human to review and, if wanted, approve (add a row to config/venues.yml). The
# closed-allowlist's "what am I NOT ingesting?" inbox. Two things feed it: an
# aggregator surfacing a venue we do not consume, and a captured place that keeps
# hosting shows.
#
# Recorded fresh per source (refresh! = delete + reinsert), so a lead that's since
# been approved or aged out of the feed simply drops off.
#
# `event_count` ranks the inbox and means two things, told apart by `source`, which
# the view renders as a chip. For an aggregator lead it is the UPCOMING events the
# venue would bring; for a capture lead (see CapturedVenueLeads) it is how many have
# EVER been captured there. The second has to count ever, or the lead evaporates as
# its shows pass and the accumulating signal — the whole basis for nominating it — is
# destroyed. One column, because a second would be null for every row of one kind.
#
# (Was VenuePlace, which fed the location taxonomy until the venue registry took that
# over.)
class VenueLead < ApplicationRecord
  validates :venue, :source, presence: true

  scope :by_demand, -> { order(event_count: :desc, venue: :asc) }

  # Replace this source's leads with the current run's set (idempotent per run).
  # `leads` is an array of { venue:, locality:, canton:, event_count: } hashes.
  def self.refresh!(source:, leads:)
    transaction do
      where(source: source).delete_all
      leads.each { |attrs| create!(attrs.merge(source: source)) }
    end
  end
end
