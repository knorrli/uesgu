module EventCapture
  # The publish half of the funnel, and the first thing in it that writes —
  # everything here has already passed a human on the capture screen.
  class Creator
    # The seam that keeps a captured event out of the scrapers' nightly
    # re-derivation. Not a scraper source_key, and deliberately one value for the
    # whole funnel: which door it came through is not a property of the event.
    DATA_SOURCE = "capture".freeze

    Result = Data.define(:event, :place, :error) do
      def initialize(event: nil, place: nil, error: nil) = super
      def ok? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(attributes)
      @attrs = attributes
    end

    def call
      return Result.new(error: :incomplete) if incomplete?

      # resolve_place WRITES and publish can raise after it: without the transaction
      # a failed publish leaves an orphan place behind, with no events and no UI to
      # remove it, still feeding PlaceSuggester and the locality datalist.
      ActiveRecord::Base.transaction do
        place = resolve_place
        next Result.new(error: :place_invalid) if place.is_a?(Place) && !place.persisted?

        Result.new(event: publish(place), place: place.is_a?(Place) ? place : nil)
      end
    rescue ActiveRecord::RecordNotUnique
      # The unique index on places.fingerprint, which Place#fingerprint_available
      # cannot close: it checks before it writes, so two contributors capturing the
      # same new venue name at once both pass it and the index refuses the second.
      Result.new(error: :place_invalid)
    end

    private

    attr_reader :attrs

    # Canton is checked for the same reason locality is: Location.add_to_tree bails
    # on a blank canton too, so an event missing it is one no node of the WHERE tree
    # can reach. The form marks both required, but the form is not the only caller.
    def incomplete? = title.blank? || start_date.blank? || locality.blank? || canton.blank?

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

    # Never Time.zone.parse: it does not reject, answering midnight for "20 Uhr" and
    # "abc" alike, and it RAISES on the "25:00" a poster prints for an after-midnight
    # show — a 500 that would take the whole unpersisted batch with it.
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
      # Also runs Genre.ensure!, so captured genres join the taxonomy the same way
      # scraped ones do — and a capture carrying only non-music genres is hidden by
      # the same rule rather than by a second one written here.
      event.recompute_visibility!
      # The locality has no such hook of its own. Minting it here rather than waiting
      # for the nightly reconcile is what puts a fresh spelling in front of an admin
      # while the poster it came from is still the reason it is there.
      Locality.ensure!(event.location_list.select { |tag| Location.type_for(tag) == :locality })
      event
    end

    # A matched place carries ITS OWN locality and canton, not the form's. Both
    # lookups are by name alone, so a capture that reads "Dachstock" but "Zürich"
    # would otherwise publish tagged Zürich/ZH while Location.hierarchy nests the
    # Dachstock node under Bern — the venue chip and the canton chip disagreeing
    # about one event, and the Bern filter missing it.
    def located(place)
      return [locality, canton].compact_blank if place.nil?

      [place.name, place.locality.presence || locality, place.canton.presence || canton].compact_blank
    end

    # A registry venue gets NO Place row — the taxonomy reads the registry first, and
    # two sources of "what is a venue" is what VenuePlace was. A blank name is
    # legitimate (a show in a park), leaving the event located by locality + canton.
    def resolve_place
      return if place_name.blank?

      Location.resolve_venue(place_name) ||
        Place.create(name: place_name, locality: locality, canton: canton)
    end
  end
end
