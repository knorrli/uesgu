module Scrapers
  class Kairo < Agent
    def self.url
      URI.parse("https://www.cafe-kairo.ch/programm")
    end

    field_gaps genres: :no_field

    def event_rows
      page.css('article[id^="kultur_"]')
    end

    def skip_row?(row)
      row.at_css(".concerts_date time")&.attr("datetime").blank?
    end

    def event_url(row)
      "#{self.class.url}##{row.attr('id')}"
    end

    def event_start_time(content)
      stamp = content.at_css(".concerts_date time")&.attr("datetime").to_s
      /(?<y>\d{4})-(?<mo>\d{2})-(?<d>\d{2})T(?<h>\d{2}):(?<mi>\d{2})/ =~ stamp
      raise "Unparseable Kairo date: #{stamp.inspect}" if y.blank?

      Time.zone.local(y.to_i, mo.to_i, d.to_i, h.to_i, mi.to_i)
    end

    def event_title(content)
      content.at_css(".text h2")&.text&.squish
    end

    def event_description(content)
      content.css(".text p").map { |node| node.text.squish }.find(&:present?)
    end

    def event_genre_prose(content)
      content.css(".text p").map(&:text).join("\n")
    end
  end
end
