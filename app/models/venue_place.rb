# A [venue, city, canton] place resolved per-event by a multi-venue aggregator
# (see Scrapers::Ole aggregators). Single-venue scrapers declare their place in
# code so Location reads the taxonomy straight off them; a per-event aggregator
# can't, and once AATO flattens the tuple into three unordered location tags the
# venue/city roles are lost. Persisting the tuple here lets Location fold these
# venues into the WHERE hierarchy and type-classify them (see Location.hierarchy
# / .venue_names / .canton_codes). Populated on each sweep by the aggregator.
class VenuePlace < ApplicationRecord
  validates :venue, :source, presence: true

  # Idempotent upsert of a resolved place. Called once per distinct tuple a sweep
  # discovers (Scrapers::Ole#persist_discovered_places); the unique [venue, city,
  # canton] index makes a re-scrape a no-op.
  def self.record!(venue:, city:, canton:, source:)
    find_or_create_by!(venue: venue, city: city, canton: canton) do |place|
      place.source = source
    end
  end
end
