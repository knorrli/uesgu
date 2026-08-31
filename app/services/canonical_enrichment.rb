class CanonicalEnrichment
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
