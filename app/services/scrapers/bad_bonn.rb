module Scrapers
  class BadBonn < Agent
    def self.url
      URI.parse("https://club.badbonn.ch/program")
    end

    field_gaps description: :no_field, genres: :no_field

    def event_rows
      page.css(".program-row")
    end

    def event_url(row)
      URI.parse(row.at_css(".program-bands a")["href"]).to_s
    end

    def event_start_time(row)
      month = Date::ABBR_MONTHNAMES.index(row["data-month"])
      raise "Unknown month #{row['data-month'].inspect} on #{event_url(row)}" unless month

      hour, minute = column(row, "time").split(":").map(&:to_i)
      Time.zone.local(row["data-year"].to_i, month, column(row, "day").to_i, hour, minute)
    end

    def event_title(row)
      column(row, "bands")
    end

    private

    def column(row, name)
      row.at_css(".program-#{name}").text.squish
    end
  end
end
