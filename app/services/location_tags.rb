class LocationTags
  Result = Data.define(:names, :place) do
    def initialize(names: [], place: nil) = super

    def place_invalid? = place.present? && !place.persisted?
  end

  def self.call(...) = new(...).call

  def initialize(place:, locality:, canton:)
    @typed = place.to_s.strip
    @locality = Locality.canonical_name(locality.to_s.strip)
    @canton = canton.to_s.strip
  end

  def call
    resolved = resolve
    names = named(resolved)
    place = resolved if resolved.is_a?(Place)
    return Result.new(names: names, place: place) if place&.new_record?

    Locality.ensure!(names.select { |name| Location.type_for(name) == :locality })
    Result.new(names: names, place: place)
  end

  private

  attr_reader :typed, :locality, :canton

  def named(place)
    return [locality, canton].compact_blank if place.nil?

    [place.name, place.locality.presence || locality, place.canton.presence || canton].compact_blank
  end

  def resolve
    return if typed.blank?

    Location.resolve_venue(typed) || Place.create(name: typed, locality: locality, canton: canton)
  end
end
