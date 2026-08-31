module Scrapers
  class Helsinki < Agent
    def self.url
      URI.parse("https://www.helsinkiklub.ch/")
    end

    def initialize
      super
      @scrape_date = Date.current
    end

    field_gaps genres: :no_field

    def event_rows
      page.css("div.event")
    end

    def event_url(row)
      id = row.attr("id")
      "#{self.class.url}##{id}" if id.present?
    end

    def event_start_time(content)
      day = content.at_css(".date .day")&.text&.squish
      month = month_number(month: content.at_css(".date .month")&.text&.squish)
      raise "Unparseable Helsinki date: #{content.at_css('.date')&.text&.squish.inspect}" if day.blank? || !month.is_a?(Integer)

      hour, minute = show_time(content.at_css(".showtime")&.text.to_s)
      Time.zone.local(year_for(month, day.to_i), month, day.to_i, hour, minute)
    end

    def event_title(content)
      top = content.at_css(".agenda .top")
      title = top&.children&.select(&:text?)&.map { |n| n.text.squish }&.compact_blank&.join(" ")
      title.presence || content.at_css(".agenda .support")&.text&.squish
    end

    def event_description(content)
      support = content.css(".agenda .support").map { |node| node.text.squish }.compact_blank.join(", ").presence
      support unless support == event_title(content)
    end

    def event_genre_prose(content)
      content.css(".description p").map(&:text).join("\n")
    end

    private

    def show_time(text)
      segment = text[/Show.*/i] || text
      if (m = segment.match(/(\d{1,2})[:.](\d{2})/))
        [m[1].to_i, m[2].to_i]
      elsif (m = segment.match(/(\d{1,2})[\s\p{Zs}]*Uhr/i))
        [m[1].to_i, 0]
      else
        [0, 0]
      end
    end

    def year_for(month, day)
      year = @scrape_date.year
      year += 1 if Date.new(year, month, day) < @scrape_date
      year
    end
  end
end
