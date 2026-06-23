module Scrapers
  class Treibhaus < Agent
    def self.location
      "Treibhaus"
    end

    def self.locations
      [location, "Luzern", "LU"]
    end

    # `?filter=konzerte` is server-rendered and keeps only live concerts (the
    # unfiltered programme mixes in quiz nights, public-viewings, e-sports, etc.),
    # so the music filter is done by URL — no per-event detail fetch needed. Club
    # /DJ nights live under a separate `?filter=club` view (not included here).
    def self.url
      URI.parse("https://www.treibhausluzern.ch/programm?filter=konzerte")
    end

    def event_rows
      page.css(".programm-list li.mb-10")
    end

    def event_url(row)
      link = row.at_css("a")
      return if link.blank?

      URI.join(self.class.url, link.attr("href")).to_s
    end

    # The <time datetime> carries a German "Monat TT, JJJJ" date WITH the year, but
    # its clock is a dummy 00:00 — the real start time is the HH:MM span beside it.
    def event_start_time(content)
      time_node = content.at_css("time")
      date_string = time_node&.attr("datetime").to_s
      /(?<month>\p{L}+)\s+(?<day>\d{1,2}),\s+(?<year>\d{4})/ =~ date_string
      raise "Unparseable Treibhaus date: #{date_string.inspect}" if day.blank? || month.blank? || year.blank?

      time_string = time_node.text[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{year}-#{month_number(month: month)}-#{day} #{time_string}")
    end

    def event_title(content)
      content.at_css("h3")&.text&.squish
    end

    def event_description(content)
      content.at_css("p.font-medium")&.text&.squish
    end
  end
end
