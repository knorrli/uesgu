module EventCapture
  class Creator
    DATA_SOURCE = "capture".freeze

    Result = Data.define(:event, :place, :canonical, :matches, :error) do
      def initialize(event: nil, place: nil, canonical: nil, matches: [], error: nil) = super
      def ok? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(attributes)
      @attrs = attributes
    end

    def call
      return Result.new(error: :incomplete) if incomplete?

      matched = matched_event
      if matched.nil? && !acknowledged?
        found = duplicates
        return Result.new(error: :duplicate, matches: found) if found.any?
      end

      ActiveRecord::Base.transaction do
        place = resolve_place
        next Result.new(error: :place_invalid) if place.is_a?(Place) && !place.persisted?

        event = publish(place)
        settle(event, matched)
        Result.new(event: event, canonical: matched, place: place.is_a?(Place) ? place : nil)
      end
    rescue ActiveRecord::RecordNotUnique
      Result.new(error: :place_invalid)
    end

    private

    attr_reader :attrs

    def incomplete? = title.blank? || start_date.blank? || locality.blank? || canton.blank?

    def matched_event
      id = attrs[:matched_event_id].presence
      id && Event.kept.canonical.find_by(id: id)
    end

    def acknowledged? = attrs[:acknowledged].present?

    def duplicates
      DuplicateFinder.for(title: title, date: start_date, place: place_name, locality: locality)
    end

    def settle(event, matched)
      if matched
        event.merge_into!(matched)
        CanonicalEnrichment.call(matched, Event.where(canonical_event_id: matched.id).to_a)
      elsif acknowledged?
        event.mark_standalone!
      end
    end

    def title = attrs[:title].to_s.strip
    def description = attrs[:description].to_s.strip.presence
    def locality = @locality ||= Locality.canonical_name(attrs[:locality].to_s.strip)
    def canton = attrs[:canton].to_s.strip
    def place_name = attrs[:place].to_s.strip
    def genres = Array(attrs[:genres]).map { |g| g.to_s.strip }.compact_blank

    # Strict ISO, not Date.parse: Date.parse("next Friday") does not raise, it
    # returns a date near today — the same silent-today footgun the scrapers hit
    # with Time.zone.parse. The field is a date input and the normalizer already
    # nulls anything non-ISO, so the only thing lenience could buy here is a
    # confidently wrong event date nobody would spot.
    def start_date
      @start_date ||= attrs[:date].present? && Date.strptime(attrs[:date].to_s, "%Y-%m-%d") || nil
    rescue Date::Error
      nil
    end

    def start_time
      return if start_date.blank?

      clock = Clock.parse(attrs[:time])
      clock.present? ? Time.zone.parse("#{start_date} #{clock}") : nil
    end

    def publish(place)
      event = Event.new(
        title: title, description: description, start_date: start_date,
        start_time: start_time, data_source: DATA_SOURCE,
        location_list: located(place),
        genre_list: genres
      )
      event.save!
      event.recompute_visibility!
      Locality.ensure!(event.location_list.select { |tag| Location.type_for(tag) == :locality })
      event
    end

    def located(place)
      return [locality, canton].compact_blank if place.nil?

      [place.name, place.locality.presence || locality, place.canton.presence || canton].compact_blank
    end

    def resolve_place
      return if place_name.blank?

      Location.resolve_venue(place_name) ||
        Place.create(name: place_name, locality: locality, canton: canton)
    end
  end
end
