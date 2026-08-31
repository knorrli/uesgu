module Scrapers
  class Mokka < Agent
    field_gaps genres: :no_field

    PER_PAGE = 100
    MAX_PAGES = 6

    def self.endpoint(page)
      URI.parse("https://mokka.ch/wp-json/wp/v2/events?per_page=#{PER_PAGE}&page=#{page}")
    end

    def self.url
      endpoint(1)
    end

    def event_rows
      rows = upcoming_from(page.body)
      page_num = 2
      while page_num <= MAX_PAGES && (resp = get(self.class.endpoint(page_num)))
        batch = upcoming_from(resp.body)
        break if batch.empty?

        rows.concat(batch)
        page_num += 1
      end
      rows
    end

    def event_url(row)
      return row["link"].presence if row.dig("acf", "has_detail_page")

      external = row.dig("acf", "external_link")
      url = external.is_a?(Hash) ? external["url"].presence : nil
      url && "#{url}#mokka-#{row.dig('acf', 'event_date')}"
    end

    def self.event_url_pattern
      %r{\Ahttps://}
    end

    def event_start_time(row)
      date = row.dig("acf", "event_date").to_s
      raise "Unparseable Mokka date: #{date.inspect}" unless date.match?(/\A\d{8}\z/)

      time = time_of(row, "event_start") || time_of(row, "event_opening")
      Time.zone.parse("#{date[0, 4]}-#{date[4, 2]}-#{date[6, 2]} #{time}")
    end

    def event_title(row)
      decode(row.dig("title", "rendered"))
    end

    def event_description(row)
      decode(row.dig("acf", "event_subtitle")).presence
    end

    def event_genre_prose(row)
      blocks = Array(row.dig("acf", "elements")).map { |el| el["wysiwyg"] }
      html = [row.dig("acf", "event_subtitle"), *blocks].compact.join("\n")
      decode(html.gsub(/<[^>]+>/, " "))
    end

    def event_cancelled?(event, row)
      super || CANCELLATION_MARKER.match?(row.dig("acf", "event_state").to_s)
    end

    private

    def upcoming_from(body)
      Array(parse_json(body)).select do |e|
        date = e.dig("acf", "event_date").to_s
        date.match?(/\A\d{8}\z/) && (Date.strptime(date, "%Y%m%d") >= Date.current)
      end
    end

    def time_of(row, key)
      row.dig("acf", key).to_s[/\d{1,2}[.:]\d{2}/]&.tr(".", ":")
    end

    def decode(html)
      CGI.unescapeHTML(html.to_s).squish
    end
  end
end
