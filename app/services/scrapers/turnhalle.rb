module Scrapers
  # The PROGR Turnhalle in Bern has no standalone site; its concerts are
  # programmed by bee-flat (which also books other rooms), so scrape the bee-flat
  # agenda and keep only the Turnhalle dates. See scraper_review.md — this venue
  # is the ambiguous one and may warrant the PROGR house agenda instead.
  class Turnhalle < Agent
    def self.location
      "Turnhalle"
    end

    def self.locations
      [location, "Bern", "BE"]
    end

    def self.url
      URI.parse("https://www.bee-flat.ch/programm/aktuell/")
    end

    def initialize
      super
      @scrape_date = Date.current
    end

    # bee-flat exposes no genre/style/tag field — the `.style` div is a venue
    # tagline ("a perfect celebration of Joni Mitchell", a tour/album name), not
    # a genre, so it feeds the description below rather than genres.
    field_gaps genres: :no_field

    def event_rows
      page.css("article.event.tile")
    end

    # bee-flat books several venues; the row's date block names the room, so keep
    # only Turnhalle nights.
    def skip_row?(row)
      !row.at_css(".date")&.text.to_s.include?("Turnhalle")
    end

    def event_url(row)
      link = row.at_css("a")
      return if link.blank?

      URI.join(self.class.url, link.attr("href")).to_s
    end

    # German "TT. Monat" with NO year (e.g. "10. Oktober") plus an "HH:MM Uhr"
    # time, both in the date block — infer the year as the next occurrence.
    def event_start_time(content)
      text = content.at_css(".date")&.text.to_s
      /(?<day>\d{1,2})\.\s*(?<month>\p{L}+)/ =~ text
      raise "Unparseable Turnhalle date: #{text.squish.inspect}" if day.blank? || month.blank?

      month = month_number(month: month)
      time_string = text[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{year_for(month, day.to_i)}-#{month}-#{day} #{time_string}")
    end

    # The band name is a bare text node in the <h2>, flanked by a country-origin
    # and an album-release span — keep only the text nodes.
    def event_title(content)
      content.at_css("h2")&.children&.select(&:text?)&.map { |n| n.text.squish }&.compact_blank&.join(" ")
    end

    # bee-flat's `.style` div is the event's tagline (tour/album name or a short
    # descriptor) — venue-authored "valuable additional info", so use it as the
    # description. Absent on the odd row, hence nil-safe.
    def event_description(content)
      content.at_css(".style")&.text&.squish.presence
    end

    private

    def year_for(month, day)
      year = @scrape_date.year
      year += 1 if Date.new(year, month, day) < @scrape_date
      year
    end
  end
end
