module Scrapers
  class Zent < Agent
    def self.location
      "Zent"
    end

    # Restaurant Zent — the bistro-with-stage inside the bimano complex at
    # Zentweg 1A, Bern. The music programme lives on restaurant-zent.ch, not
    # bimano.ch (which is the bouldering/booking side).
    def self.locations
      [location, "Bern", "BE"]
    end

    def self.url
      URI.parse("https://restaurant-zent.ch/kulturprogramm")
    end

    def event_rows
      page.css("article.event-item")
    end

    def event_url(row)
      link = row.at_css("a.permalink")
      return if link.blank?

      URI.join("https://restaurant-zent.ch", link.attr("href")).to_s
    end

    # Clean <time>DD.MM.YYYY</time> with the year present (no silent-today risk).
    # Start time appears only as German prose ("Türöffnung 18.30"), so it is left
    # unparsed and the event defaults to the date at midnight.
    def event_start_time(content)
      date_string = content.at_css("time")&.text&.squish
      raise "Unparseable Zent date: #{date_string.inspect}" unless date_string =~ /\d{1,2}\.\d{1,2}\.\d{4}/

      Time.zone.parse(date_string)
    end

    def event_title(content)
      content.at_css("h2, h1")&.text&.squish
    end
  end
end
