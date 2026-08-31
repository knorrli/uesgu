module Scrapers
  class LeSinge < Agent
    def self.endpoint(offset)
      URI.parse("https://kartellculturel.ch/getEvents?startDate=#{Date.current.iso8601}&lang=de&offset=#{offset}&location=1")
    end

    def self.url
      endpoint(0)
    end

    def event_rows
      events = data_from(page.body)
      offset = 10
      while (resp = get(self.class.endpoint(offset)))
        batch = data_from(resp.body)
        break if batch.empty?

        events.concat(batch)
        offset += 10
      end
      events
    end

    def event_url(row)
      row["detailUrl"].presence
    end

    def event_start_time(row)
      date = row["startDate"].to_s[/\d{4}-\d{2}-\d{2}/]
      raise "Unparseable Le Singe date: #{row['startDate'].inspect}" if date.blank?

      time = row["startTime"].to_s.tr("h", ":")[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{date} #{time}")
    end

    def event_title(row)
      row["nameBand"].presence || row["title"]
    end

    def event_description(row)
      row["subTitle"].presence
    end

    def event_genres(row)
      Array(row["genres"]).map { |g| g.to_s.squish }.compact_blank
    end

    def event_cancelled?(_event, row)
      row["isCancelled"] == true
    end

    private

    def data_from(body)
      parse_json(body, default: {}).fetch("data", [])
    end
  end
end
