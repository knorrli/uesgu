module Scrapers
  class Marians < Agent
    def self.url
      URI.parse("https://www.mariansjazzroom.ch/termine-marians")
    end

    def event_rows
      page.css(".eventlist-event--upcoming")
    end

    def skip_row?(row)
      title = row_title(row)
      title.blank? || title.match?(/Informationen folgen/i)
    end

    def event_url(row)
      link = row.at_css("a.eventlist-title-link, a.eventlist-column-thumbnail")
      return if link.nil?

      URI.join(self.class.url, link.attr("href")).to_s
    end

    def event_content(row)
      click(Page::Link.new(row.at_css("a.eventlist-title-link"), @mech, page))
    end

    def event_start_time(content)
      Time.zone.parse(event_ld(content).fetch("startDate"))
    end

    def event_title(content)
      event_ld(content)["name"].to_s.sub(/\s*[—–-]\s*Marians Jazzroom\z/, "").strip
    end

    def event_description(content)
      content.at_css(".eventitem-column-content h2")&.text&.squish.presence
    end

    def event_genres(_content)
      ["Jazz"]
    end

    def event_genre_prose(content)
      content.at_css(".eventitem-column-content")&.text
    end

    private

    def row_title(row)
      row.at_css(".eventlist-title-link")&.text.to_s.strip
    end

    def event_ld(content)
      node = content.css('script[type="application/ld+json"]')
                    .map { |s| JSON.parse(s.text) rescue nil }
                    .compact.find { |d| d["@type"] == "Event" }
      node || raise("No Event JSON-LD on #{content.uri}")
    end
  end
end
