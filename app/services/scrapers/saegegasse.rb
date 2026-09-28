module Scrapers
  class Saegegasse < Agent
    self.opens_event_pages = true

    def self.url
      URI.parse("https://www.saegegasse.ch/programm")
    end

    field_gaps genres: :no_field

    def event_rows
      page.css(".rs_events_container .rs_event_detail")
    end

    def event_url(row)
      absolute_url(row.at_css("a.rs_event_link").attr("href"))
    end

    def event_start_time(content)
      date_string = content.at_css('meta[itemprop="startDate"]')&.attr("content")
      raise "Unparseable date #{date_string.inspect}" if date_string.blank?

      Time.zone.parse(date_string)
    end

    def event_title(content)
      content.css(".rsepro-title-block").text.squish
    end

    def event_description(content)
      content.css(".rsepro-small-description-block").text.squish
    end

    def event_genre_prose(row)
      event_page(row).css("#artikeltext .description").map(&:text).join("\n")
    end

    def event_media(row) = Media.in(event_page(row))
  end
end
