module Scrapers
  class XTra < Agent
    OWN_ROOM = /\AX-TRA\b/
    XHR = { "X-Requested-With" => "XMLHttpRequest" }.freeze

    def self.url
      URI.parse("https://www.x-tra.ch/de/programm/konzerte/")
    end

    def self.event_url_pattern
      %r{\Ahttps://www\.x-tra\.ch/de/programm/konzerte/\d+/}
    end

    field_gaps description: :no_field

    def event_rows
      tiles(page.parser) + tiles(remaining_events)
    end

    def skip_row?(row)
      room = info(detail_page(row), "Location")
      room.present? && !OWN_ROOM.match?(room)
    rescue StandardError
      false
    end

    def event_url(row)
      absolute_url(link_for(row).href)
    end

    def event_content(row)
      detail_page(row)
    end

    def event_start_time(content)
      start = structured_data(content)["startDate"]
      raise "Missing X-TRA start for #{event_title(content).inspect}" if start.blank?

      Time.zone.parse(start)
    end

    def event_title(content)
      content.at_css(".featured .caption h2")&.text&.squish
    end

    def event_genres(content)
      info(content, "Musikstil").to_s.split(%r{[/,]}).map(&:squish).compact_blank
    end

    private

    def tiles(document)
      document.css("ul.tile > li").to_a
    end

    def remaining_events
      response = post(self.class.url, { action: "column_events_load_more", csrf_token: csrf_token }, XHR)
      return Nokogiri::HTML.fragment("") if response.blank?

      payload = parse_json(response.body, default: {})
      Rails.logger.error("[#{self.class.location}] more events unavailable: #{payload['error']}") if payload["events"].nil?
      Nokogiri::HTML.fragment(payload["events"].to_s)
    rescue Mechanize::Error => e
      Rails.logger.error("[#{self.class.location}] more events unavailable: #{e.class}: #{e.message}")
      Nokogiri::HTML.fragment("")
    end

    def csrf_token
      page.at_css('meta[name="csrf-token"]')&.[]("content")
    end

    def link_for(row)
      Page::Link.new(row.at_css("a"), @mech, page)
    end

    def detail_page(row)
      return @detail_page if @detail_row.equal?(row)

      @detail_page = click(link_for(row))
      @detail_row = row
      @detail_page
    end

    def info(content, label)
      item = content.css(".event ul.info li").find { |li| li.at_css("span")&.text&.squish == label }
      item&.at_css("strong")&.text&.squish.presence
    end

    def structured_data(content)
      script = content.at_css('script[type="application/ld+json"]')&.text
      data = script.present? ? parse_json(script, default: {}) : {}
      data.is_a?(Hash) ? data : {}
    end
  end
end
