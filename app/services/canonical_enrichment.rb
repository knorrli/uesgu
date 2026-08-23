# What a canonical event takes from the duplicates folded onto it: their genres,
# unioned, and any field the canonical itself has none of.
#
# Re-derived from scratch on every call rather than written once, and that is the
# whole design. It is what lets a contributor's capture enrich a scraped listing
# without pinning anything: the scraper re-sets its own event's fields from source
# each sweep and this then fills only what is STILL blank, so the venue's own value
# wins the moment there is one. Pinning (Event#lock_field!) would instead freeze the
# field for good, and a description the venue publishes next week would never land.
#
# Run at the end of a sweep by Scrapers::Dedup, and again inline by
# EventCapture::Creator, so a contributor sees what their read added instead of
# waiting a night for the same call to reach the same answer.
class CanonicalEnrichment
  # Columns a duplicate may fill when the canonical has none.
  #
  # `title` and `start_date` are absent because they are what matched the two in the
  # first place, and `url` because it is the scrapers' upsert key under a unique
  # index — copying one across would strand the row it came from on the next run.
  FILLABLE = %i[description start_time].freeze

  def self.call(...) = new(...).call

  def initialize(canonical, duplicates)
    @canonical = canonical
    @duplicates = Array(duplicates)
  end

  def call
    return if duplicates.empty?

    filled = fill_blanks
    regenred = merge_genres
    return unless filled || regenred

    # Visibility is a projection of the genres that now stand, so a captured genre
    # can lift the music gate off an event the scraped copy's genres had hidden.
    canonical.recompute_visibility!
  end

  private

  attr_reader :canonical, :duplicates

  def fill_blanks
    FILLABLE.select { |field| fill(field) }.any?
  end

  def fill(field)
    return false if canonical.public_send(field).present?

    value = duplicates.map { |duplicate| duplicate.public_send(field) }.compact_blank.first
    return false if value.blank?

    canonical.public_send(:"#{field}=", value)
    true
  end

  def merge_genres
    merged = (canonical.genre_list + duplicates.flat_map(&:genre_list)).uniq
    return false if merged.sort == canonical.genre_list.sort

    canonical.genre_list = merged
    true
  end
end
