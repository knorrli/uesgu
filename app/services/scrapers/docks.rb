module Scrapers
  class Docks < Agent
    def self.url
      URI.parse("https://www.docks.ch/programme")
    end

    def event_rows
      page.css(".programme-container .mix.concerts")
    end

    def event_url(row)
      URI.parse(link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    def event_start_time(content)
      date_string = content.css(".event-infos .event-info-date").text.squish[/\d{1,2}\.\d{1,2}\.\d{4}/]
      time_string = content.css(".event-infos .event-info-door").last.text.squish[/\d{2}:\d{2}/]
      Time.zone.parse("#{date_string}, #{time_string}")
    end

    def event_title(content)
      content.css(".top-event-container h1").text.squish
    end

    def event_description(content)
      content.css(".event-subtitle").text.split("+").map { |part| part.squish }.compact_blank.join(", ")
    end

    def event_genres(content)
      content.css(".artist-item .artist-info")
             .map { |node| node.text.squish }
             .compact_blank
             .reject { |tag| origin_code?(tag) }
             .map { |tag| tag.titleize }
             .uniq.sort
    end

    private

    def origin_code?(tag)
      tag.match?(/\A[A-Za-z]{2}\z/)
    end

    def link_for(row)
      Page::Link.new(row.at_css("a"), @mech, page)
    end
  end
end
