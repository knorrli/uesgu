require "nokogiri"

module Scrapers
  class Petzi < Agent
    def self.venues
      Venue.all.each_with_object({}) do |venue, map|
        Array(venue.aliases["petzi"]).each { |slug| map[slug] = venue.place_tuple }
      end
    end

    def self.domains
      Venue.all.each_with_object({}) do |venue, map|
        Array(venue.aliases["petzi"]).each { |slug| map[slug] = venue.domain }
      end
    end

    def self.venue_domains = domains.values

    def self.url
      URI.parse("https://www.petzi.ch/en/sitemap.xml")
    end

    def self.location
      "PETZI"
    end

    def self.locations
      [location]
    end

    def self.aggregator?
      true
    end

    field_gaps description: :no_field

    def event_rows
      xml = Nokogiri::XML(page.body)
      xml.remove_namespaces!
      xml.css("loc").map(&:text).select { |u| u.include?("/events/") && venue_for(u) }
    end

    def event_url(row) = venue_url(detail_page(row), row) || row

    def event_content(row) = detail_page(row)

    def event_start_time(content)
      date = title_parts(content).find { |p| p =~ %r{\A\d{2}\.\d{2}\.\d{4}\z} }
      raise "Unparseable PETZI date for #{current_row}" if date.blank?

      d, m, y = date.split(".").map(&:to_i)
      hour, minute = show_or_doors(content)
      Time.zone.local(y, m, d, hour, minute)
    end

    def event_title(content)
      squish(content.parser.at_css("h1")&.text)
    end

    def event_genres(content)
      content.parser.css("a.tag").map { |a| squish(a.text) }.reject(&:blank?).uniq
    end

    def event_locations(_content)
      venue_for(current_row)
    end

    private

    def squish(str) = str.to_s.gsub(/\s+/, " ").strip

    def title_parts(content)
      squish(content.parser.at_css("title")&.text).split(" / ")
    end

    def show_or_doors(content)
      body = squish(content.parser.text)
      time = body[/Event starts at:\s*(\d{1,2})[:.](\d{2})/i, 0] ||
             body[/Doors open at:\s*(\d{1,2})[:.](\d{2})/i, 0]
      return [0, 0] unless time

      m = time.match(/(\d{1,2})[:.](\d{2})/)
      [m[1].to_i, m[2].to_i]
    end

    def detail_page(row)
      if @detail_row != row
        @detail_row  = row
        @detail_page = get(row)
      end
      @detail_page
    end

    def venue_url(page, row)
      domain = self.class.domains[slug_for(row)]
      return if domain.blank?

      page.links.filter_map(&:href)
          .find { |href| href.start_with?("http") && Scrapers::Discovery.domain(href) == domain }
    end

    def slug_for(url)
      self.class.venues.keys.find { |s| url =~ %r{/events/\d+-#{Regexp.escape(s)}-} }
    end

    def venue_for(url) = self.class.venues[slug_for(url)]
  end
end
