require "nokogiri"
require "cgi"

module Scrapers
  class Ole < Agent
    Row = Struct.new(:event, :show, :start_time, :url, :locations, keyword_init: true)

    STOP_AFTER_EMPTY_PAGES = 3

    REPEAT_DROP_THRESHOLD = 5

    # Registerable keys the registry on `child_class.name`, which is nil while
    # Ruby fires `inherited` for the Class.new subclasses `build` returns.
    # Suppressed here (no super); the loop at the bottom of this file names each
    # one and registers it.
    def self.inherited(child)
    end

    class << self
      attr_accessor :feed_url, :place, :is_aggregator, :label, :provenance, :link_via, :gate

      def strict? = gate != :lenient

      def feed_key(venue)
        ActiveSupport::Inflector.transliterate(venue.name).gsub(/[^a-zA-Z0-9]/, "")
      end

      def build(key:, feed_url:, place: nil, aggregator: false, link_via: :venue, gate: :strict)
        Class.new(self) do
          self.feed_url      = feed_url
          self.place         = place
          self.is_aggregator = aggregator
          self.label         = key
          self.provenance    = "OLE:#{key}"
          self.link_via      = link_via
          self.gate          = gate
        end
      end

      def url = URI.parse(feed_url)

      def location = place ? place.first : label

      def locations = place || [location]

      def aggregator? = !!is_aggregator

      def venue_domains
        own = [Discovery.domain(url.host)].compact
        return own unless aggregator?

        own + Venue.all.select { |v| v.consume? && v.aggregator_names.include?(label) }.map(&:domain)
      end

      def source_key = provenance
    end

    def call
      result = super
      persist_leads
      result
    end

    def event_rows
      rows = []
      doc = current_doc
      pages = 1
      empty_streak = 0
      loop do
        page_rows = rows_from(doc)
        rows.concat(page_rows)

        empty_streak = page_rows.empty? ? empty_streak + 1 : 0
        break if rows.any? && empty_streak >= STOP_AFTER_EMPTY_PAGES

        nxt = next_url(doc)
        break if nxt.blank?

        cap = max_pages(doc)
        break if cap.positive? && pages >= cap

        get(nxt)
        doc = current_doc
        pages += 1
      end
      record_lead_frequencies(rows)
      rows
    end

    def event_url(row) = row.url

    def event_start_time(row) = row.start_time

    def event_title(row) = clean_title(text(row.event, "name"))

    def event_description(row)
      return nil unless description_present?(row.event)
      return nil if repeated_house_blurb?(row.event)

      plain_text(text(row.event, "lead")).presence
    end

    def event_genres(row)
      row.event.css("categories category").map { |c| squish(decode(c.text)) }.reject(&:blank?).uniq
    end

    def event_locations(row) = row.locations

    def skip_row?(row)
      return false unless self.class.aggregator?
      return false if Venue.matching(row.locations.first)&.consume?

      self.class.strict?
    end

    private

    def current_doc
      doc = Nokogiri::XML(page.body)
      doc.remove_namespaces!
      doc
    end

    def rows_from(doc)
      doc.css("event").flat_map do |event_node|
        base_url = event_base_url(event_node)
        next [] if base_url.blank?

        locations = locations_for(event_node)
        rows = event_node.css("shows show").filter_map do |show_node|
          start = parse_start(show_node)
          next if start.nil? || start.to_date < Date.current

          Row.new(event: event_node, show: show_node, start_time: start,
                  url: occurrence_url(base_url, start), locations: locations)
        end
        note_place(locations, rows.size) if rows.any?
        rows
      end
    end

    def event_base_url(event_node)
      venue = decode(text(event_node, "url"))
      return venue unless self.class.link_via == :source

      venue_event_link?(venue) ? venue : decode(text(event_node, "source_url")).presence
    end

    def decode(raw) = raw.blank? ? raw : CGI.unescapeHTML(raw)

    def venue_event_link?(url)
      return false if url.blank?

      uri = URI.parse(url)
      return true if uri.query.present?

      uri.path.to_s.split("/").any? { |seg| seg.match?(/\d/) }
    rescue URI::InvalidURIError
      false
    end

    def parse_start(show_node)
      raw = text(show_node, "date_start")
      return nil if raw.blank?

      Time.zone.parse(raw)
    rescue ArgumentError => e
      Rails.logger.warn("[#{self.class.location}] unparseable OLE date_start #{raw.inspect}: #{e.message}")
      nil
    end

    def occurrence_url(base_url, start)
      "#{base_url}#show-#{start.to_date.iso8601}"
    end

    LOCALITY_CANTON_FIXES = { "wabern" => "BE" }.freeze

    def locations_for(event_node)
      return self.class.locations unless self.class.aggregator?

      loc      = event_node.at_css("location")
      venue    = clean_title(text(loc, "name"))
      locality = squish(text(loc, "locality"))
      canton   = LOCALITY_CANTON_FIXES[locality.downcase] || SwissPostcode.canton(text(loc, "code"))
      [venue, locality, canton].compact_blank.presence || self.class.locations
    end

    def note_place(locations, count)
      return unless self.class.aggregator? && locations.size >= 2

      (@discovered_places ||= Hash.new(0))[locations] += count
    end

    def persist_leads
      return unless self.class.aggregator?

      leads = (@discovered_places || {}).filter_map do |(venue, locality, canton), count|
        next if Venue.matching(venue)

        { venue: venue, locality: locality, canton: canton, event_count: count }
      end
      VenueLead.refresh!(source: self.class.source_key, leads: leads)
    end

    def text(node, css)
      node&.at_css(css)&.text
    end

    def description_present?(event_node)
      text(event_node, "description").to_s
        .gsub(/<[^>]+>/, " ")
        .gsub(/&[^;\s]+;/, " ")
        .strip.present?
    end

    def record_lead_frequencies(rows)
      @lead_counts = Hash.new(0)
      rows.map(&:event).uniq.each do |event_node|
        lead = normalized_lead(event_node)
        @lead_counts[lead] += 1 if lead.present?
      end
    end

    def normalized_lead(event_node) = plain_text(text(event_node, "lead"))

    def repeated_house_blurb?(event_node)
      lead = normalized_lead(event_node)
      return false if lead.blank?

      (@lead_counts || {}).fetch(lead, 0) >= REPEAT_DROP_THRESHOLD
    end

    def plain_text(html) = squish(Nokogiri::HTML.fragment(html.to_s).text)

    def squish(str) = str.to_s.gsub(/\s+/, " ").strip

    def clean_title(str) = squish(decode(str)).sub(/\s*:\z/, "")

    def next_url(doc) = squish(text(doc, "meta next_url"))

    def max_pages(doc) = text(doc, "meta max_pages").to_i
  end

  All.scrapers.delete(Ole.name.demodulize)

  Venue.consuming.each do |venue|
    venue.ole_feeds.each do |feed|
      key   = Ole.feed_key(venue)
      const = "Ole#{key}"
      klass = Ole.build(key: key, feed_url: feed.feed_url,
                        place: feed.aggregator_feed? ? nil : venue.place_tuple,
                        aggregator: feed.aggregator_feed?,
                        link_via: (feed.link_via || "venue").to_sym,
                        gate: (feed.gate || "strict").to_sym)
      Scrapers.const_set(const, klass)
      All.scrapers[const] = klass
    end
  end
end
