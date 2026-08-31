module Scrapers
  class Volkshaus < Agent
    def self.url
      URI.parse("https://volkshaus-basel.ch/programm/")
    end

    field_gaps genres: :no_field

    def event_rows
      page.css("#programmliste .tableitem.event")
    end

    def skip_row?(row)
      !row.classes.include?("genre-musik")
    end

    def event_url(row)
      anchor = row.at_css("a.toggle-link")&.attr("href")
      return if anchor.blank?

      URI.join(self.class.url, anchor).to_s
    end

    def event_start_time(content)
      cell = content.at_css(".col-sm-3")&.text.to_s
      date_string = cell[%r{\d{1,2}\.\d{1,2}\.\d{4}}]
      raise "Unparseable Volkshaus date: #{cell.squish.inspect}" if date_string.blank?

      time_string = cell[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{date_string} #{time_string}")
    end

    def event_title(content)
      content.at_css("a.toggle-link h4")&.text&.squish
    end

    def event_description(content)
      content.css(".panel-collapse .col-sm-8 p").map { |node| node.text.squish }.find(&:present?)
    end

    def event_genre_prose(content)
      content.css(".panel-collapse .col-sm-8 p").map(&:text).join("\n")
    end
  end
end
