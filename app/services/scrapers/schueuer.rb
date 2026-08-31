module Scrapers
  class Schueuer < Agent
    def self.url
      URI.parse("https://www.schuur.ch/programm")
    end

    def event_rows
      page.css(".viz-event-list-box")
    end

    def event_url(row)
      URI.parse(row.at_css("a.viz-event-box-details-link").attr("href").to_s).to_s
    end

    def skip_row?(row)
      raw = date_text(row)
      return false if parse_start_time(raw)

      Rails.logger.warn(
        "[#{self.class.location}] Skipping event with unparseable date #{raw.inspect}"
      )
      true
    end

    def event_start_time(content)
      parse_start_time(date_text(content))
    end

    def event_title(content)
      content.css(".viz-event-name").text.squish
    end

    def event_description(content)
      content.css(".viz-event-headline").text.squish
    end

    def event_genres(content)
      content.css(".viz-event-genre").map { |node| node.text.squish }
    end

    private

    def date_text(node)
      node.css(".viz-event-date").text.squish
    end

    def parse_start_time(text)
      return nil if text.blank?

      day   = text[/\b(\d{1,2})\./, 1]
      month = text[MONTH_WORD]
      year  = text[/\b(\d{4})\b/, 1]
      return nil if day.blank? || month.blank? || year.blank?

      text =~ /(?<hour>\d{1,2}):(?<minute>\d{1,2})/
      hour   = Regexp.last_match&.named_captures&.dig("hour")
      minute = Regexp.last_match&.named_captures&.dig("minute")

      Time.zone.parse("#{year}-#{month_number(month: month)}-#{day}, #{hour}:#{minute}")
    rescue ArgumentError => e
      Rails.logger.error("[#{self.class.location}] unparseable date #{text.inspect}: #{e.class}: #{e.message}")
      nil
    end

    MONTH_WORD = /
      \b(?:
        Jan(?:uar)? | Feb(?:ruar)? | M(?:är|rz|ärz) | Apr(?:il)? | Mai
        | Jun[i]? | Jul[i]? | Aug(?:ust)? | Sept?(?:ember)? | Okt(?:ober)?
        | Nov(?:ember)? | Dez(?:ember)?
      )\b
    /x
  end
end
