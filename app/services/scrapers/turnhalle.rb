module Scrapers
  class Turnhalle < Agent
    def self.url
      URI.parse("https://www.bee-flat.ch/programm/aktuell/")
    end

    def initialize
      super
      @scrape_date = Date.current
    end

    field_gaps genres: :no_field

    def event_rows
      page.css("article.event.tile")
    end

    def skip_row?(row)
      !row.at_css(".date")&.text.to_s.include?("Turnhalle")
    end

    def event_url(row)
      link = row.at_css("a")
      return if link.blank?

      URI.join(self.class.url, link.attr("href")).to_s
    end

    def event_start_time(content)
      text = content.at_css(".date")&.text.to_s
      /(?<day>\d{1,2})\.\s*(?<month>\p{L}+)/ =~ text
      raise "Unparseable Turnhalle date: #{text.squish.inspect}" if day.blank? || month.blank?

      month = month_number(month: month)
      time_string = text[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{year_for(month, day.to_i)}-#{month}-#{day} #{time_string}")
    end

    def event_title(content)
      content.at_css("h2")&.children&.select(&:text?)&.map { |n| n.text.squish }&.compact_blank&.join(" ")
    end

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
