module Scrapers
  class Isc < Agent
    def self.url
      URI.parse("https://isc-club.ch/")
    end

    def initialize
      super
      @scrape_date = Date.current
    end

    def event_rows
      page.css("a.event_preview")
    end

    # Only concerts; other event types are skipped.
    def skip_row?(row)
      !row.css(".event_title_info").text.squish.include?("Konzert")
    end

    def event_url(row)
      URI.parse(row.attr("href").to_s).to_s
    end

    def event_content(row)
      click(Page::Link.new(row, @mech, page))
    end

    # The detail page omits the year. ISC lists only upcoming concerts, so a
    # day/month that has already passed in the scrape year must belong to next
    # year. This covers a leading January event seen while scraping in December,
    # which the previous "roll the year forward when the date sequence wraps
    # backwards" heuristic mis-dated — the first event had nothing before it to
    # wrap against, so it kept the scrape year and landed ~12 months in the past.
    def event_start_time(content)
      date_string = content.css(".event_detail_header .event_title_date").text.squish
      time_string = content.css(".event_detail .facts_listing").text.squish[/\d{1,2}:\d{1,2} Uhr/]

      /(?<day>\d{1,2})?\.(?<month>\d{1,2})?\./ =~ date_string
      /(?<hour>\d{1,2})?:(?<minute>\d{1,2})?/ =~ time_string

      raise "Unparseable date #{date_string.inspect}" if day.blank? || month.blank?

      Time.zone.parse("#{year_for(month.to_i, day.to_i)}-#{month}-#{day}, #{hour}:#{minute}")
    end

    def event_title(content)
      content.css(".event_detail_header .event_title_title").text.squish
    end

    # ISC dropped the old header subtitle; every detail page now carries a "FFO"
    # ("for fans of") facts row instead — a curated list of kindred/inspiration
    # acts (e.g. "Slowdive, Mazzy Star, My Bloody Valentine"). That's the best
    # secondary-text we get, so surface it as the description. The live label is
    # just "FFO" (older pages spelled it "FFO (for fans of)"), hence the prefix
    # match.
    def event_description(content)
      row = content.css(".event_detail .facts_listing .facts_listing_row").find do |node|
        node.at_css(".column_left")&.text&.squish&.start_with?("FFO")
      end
      bands = row&.at_css(".column_right")&.text&.squish
      "For fans of: #{bands}" if bands.present?
    end

    def event_genres(content)
      # `event_title_info` is a structured "<event type> - <comma-separated genres>"
      # field (e.g. "Konzert - Psychedelia, Funk, Jazz-Fusion"). Drop the leading
      # type segment so "Konzert"/"Party" don't pollute the genre taxonomy, then
      # split the remainder. Genres use non-spaced hyphens ("Jazz-Fusion"), so the
      # spaced "\s-\s" only ever matches the type separator.
      info = content.css(".event_detail_header .event_title_info").text.squish
      genres = info[/\s-\s(.+)\z/, 1].to_s
      genres.split(/,|\s[au]nd\s/).map(&:squish).compact_blank
    end

    private

    # The scrape year, advanced by one when this day/month has already passed —
    # ISC never lists events more than a year out, so the next occurrence is
    # unambiguous.
    def year_for(month, day)
      year = @scrape_date.year
      year += 1 if Date.new(year, month, day) < @scrape_date
      year
    end
  end
end
