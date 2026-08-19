module EventCapture
  # The publish half of the funnel, and the first thing in it that writes —
  # everything here has already passed a human on the verify screen.
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
      # the duplicate-url path leaves an orphan place behind, with no events and no
      # UI to remove it, still feeding PlaceSuggester and the locality datalist.
      ActiveRecord::Base.transaction do
        place = resolve_place
        next Result.new(error: :place_invalid) if place.is_a?(Place) && !place.persisted?

        Result.new(event: publish(place), place: place.is_a?(Place) ? place : nil)
      end
    rescue ActiveRecord::RecordNotUnique
      # The unique index on events.url. Not a 500: "this event already exists" is
      # precisely what a contributor pasting a link the scraper already has should
      # be told, and decision 10 chose that collision deliberately over a second
      # column that would let the duplicate through.
      Result.new(error: :duplicate)
    end

    private

    attr_reader :attrs

    # Canton is checked for the same reason locality is: Location.add_to_tree bails
    # on a blank canton too, so an event missing it is one no node of the WHERE tree
    # can reach. The form marks both required, but the form is not the only caller.
    def incomplete? = title.blank? || start_date.blank? || locality.blank? || canton.blank?

    def title = attrs[:title].to_s.strip
    def locality = attrs[:locality].to_s.strip
    def canton = attrs[:canton].to_s.strip
    def place_name = attrs[:place].to_s.strip
    def url = attrs[:url].presence
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
        title: title, start_date: start_date, start_time: start_time, url: url,
        data_source: DATA_SOURCE,
        location_list: located(place),
        genre_list: genres
      )
      event.save!
      # Also runs Genre.ensure!, so captured genres join the taxonomy the same way
      # scraped ones do — and a capture carrying only non-music genres is hidden by
      # the same rule rather than by a second one written here.
      event.recompute_visibility!
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

      registry = Venue.in_taxonomy.find { |venue| Fingerprint.for(venue.name) == Fingerprint.for(place_name) }
      return registry if registry

      Place.matching(place_name) ||
        Place.create(name: place_name, locality: locality, canton: canton, url: place_url)
    end

    # A capture's link is regularly an Instagram post or a ticketing page — for the
    # ad-hoc events this feature exists to catch it is often the only page there is.
    # That link belongs on the event, never on the place: places.url exists to make
    # a VenueLead ACTIONABLE ("write a scraper"), and a scraper cannot be written
    # against someone's Instagram.
    def place_url
      return if url.blank? || EventsHelper::OFFSITE_SOURCES.keys.any? { |d| host == d || host&.end_with?(".#{d}") }

      url
    end

    def host
      @host ||= URI.parse(url.to_s).host&.downcase&.delete_prefix("www.")
    rescue URI::InvalidURIError
      nil
    end
  end
end
