module Scrapers
  class Turnhalle < Agent
    AGENDA = "https://www.progr.ch/de/agenda/".freeze
    ROOM = "PROGR Turnhalle".freeze
    SUMMARY_LABEL = "Einfach gesagt:".freeze

    def self.url
      URI.parse(AGENDA)
    end

    def event_rows
      @event_rows ||= agenda_articles
    end

    def skip_row?(row)
      row.at_css(".venues")&.text&.squish != ROOM
    end

    def event_url(row)
      path = row["data-g-path"]
      return if path.blank?

      url = absolute_url(path, AGENDA)
      recurring_paths.include?(path) ? "#{url}##{row['data-g-date']}" : url
    end

    def event_start_time(row)
      date = row["data-g-date"].to_s
      raise "Unparseable PROGR date: #{date.inspect}" unless date.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      /\A(?<hour>\d{1,2})(?::(?<minute>\d{2}))?/ =~ row.at_css(".time")&.text.to_s.strip
      Time.zone.parse("#{date} #{hour || 0}:#{minute || '00'}")
    end

    def event_title(row)
      row.css(".title h2 > span:not(.invisible)").map(&:text).join(" ").squish
    end

    def event_description(row)
      summary = row.css(".details .text > p").find { |p| p.at_css("strong")&.text&.squish == SUMMARY_LABEL }
      summary&.text&.squish&.delete_prefix(SUMMARY_LABEL)&.strip.presence
    end

    def event_genres(row)
      row.at_css(".categories")&.text.to_s.split(",").map(&:squish).compact_blank
    end

    def event_genre_prose(row)
      row.at_css(".details .text")&.text
    end

    private

    def agenda_articles
      articles = page.css("article.event").to_a
      offset = page.at_css("#agendalist")&.[]("data-g-offset")
      while offset.present? && (chunk = agenda_chunk(offset))
        articles.concat(Nokogiri::HTML(chunk["data"].to_s).css("article.event").to_a)
        offset = chunk["hasmore"] == "1" ? chunk["offset"] : nil
      end
      articles
    end

    def agenda_chunk(offset)
      response = get(AGENDA, { method: "getData", offset: offset, daycount: 14 }, nil,
                     { "X-Requested-With" => "XMLHttpRequest" })
      parse_json(response.body, default: nil) if response
    end

    def recurring_paths
      @recurring_paths ||= event_rows.map { |row| row["data-g-path"] }.tally.select { |_, n| n > 1 }.keys.to_set
    end
  end
end
