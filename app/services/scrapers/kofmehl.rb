module Scrapers
  class Kofmehl < Agent
    def self.url
      URI.parse("https://kofmehl.net/")
    end

    # Kofmehl's site exposes no genre/style/tag field — its detail pages carry a
    # title + support/description only. Any genre coverage that shows up on these
    # events is incidental (PETZI ships the same shows with tags; a dedup merge or
    # an admin pin can leave a few behind), never collected here. Declared a gap
    # to record that the source itself can't deliver genres.
    field_gaps genres: :no_field

    def event_rows
      page.css(".events .events__element")
    end

    def event_url(row)
      URI.parse(link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    def event_start_time(content)
      date_string = content.css(".event__date").text.squish[/\d{1,2}\.\d{1,2}\.\d{4}/]
      time_string = content.css(".sidebar time").last&.text&.squish.try(:[], /\d{2}:\d{2}/)
      raise "Unparseable date #{content.css('.event__date').text.squish.inspect}" if date_string.blank?
      Time.zone.parse("#{date_string}, #{time_string}")
    end

    def event_title(content)
      content.css(".event__title-artist").text.squish
    end

    def event_description(content)
      support = content.css(".event__support").text.squish
      subtitle = content.css(".event__subtitle").text.squish
      [support, subtitle].compact_blank.join(", ")
    end

    private

    def link_for(row)
      Page::Link.new(row.at_css("a.events__link"), @mech, page)
    end
  end
end
