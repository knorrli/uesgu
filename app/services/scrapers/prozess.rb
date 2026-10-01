module Scrapers
  class Prozess < Agent
    def self.url
      URI.parse("https://prozess.be/content/content.json")
    end

    def self.event_url_pattern
      %r{\Ahttps://prozess\.be/programm/\d+}
    end

    field_gaps genres: :no_field

    DATE = /(\d{1,2})\.(\d{1,2})\.(\d{4})/
    TIME = /(\d{1,2}):(\d{2})/

    def event_rows
      programme.reject { |entry| entry["hidden"] }
               .flat_map { |entry| showings(entry) }
               .select { |row| row["date"] >= Date.current }
    end

    def event_url(row)
      url = "https://prozess.be/programm/#{row['entry']['id']}"
      row["series"] ? "#{url}##{row['date'].iso8601}" : url
    end

    def event_start_time(row)
      date = row["date"]
      hour, minute = row["time"].to_s.match(TIME)&.captures&.map(&:to_i)
      Time.zone.local(date.year, date.month, date.day, hour || 0, minute || 0)
    end

    def event_title(row)
      plain(row["entry"]["title"])
    end

    def event_description(row)
      paragraphs(row["entry"]["text"]).first
    end

    def event_genre_prose(row)
      [event_title(row), *paragraphs(row["entry"]["text"]), *paragraphs(row["entry"]["small"])].join("\n")
    end

    private

    def programme
      Array(JSON.parse(page.body)["programm"])
    end

    def showings(entry)
      dated = dates_of(entry).map.with_index do |date, index|
        { "entry" => entry, "date" => date, "time" => time_of(entry, index) }
      end
      dated.each { |row| row["series"] = true } if dated.size > 1
      dated
    end

    def dates_of(entry)
      if entry["date"]
        [parse_date(entry["date"])]
      elsif entry["dates"]
        entry["dates"].split(",").map { |date| parse_date(date) }
      elsif entry["lastdate"]
        timed?(entry) ? (parse_date(entry["firstdate"])..parse_date(entry["lastdate"])).to_a : []
      else
        entry.values_at("firstdate", "seconddate", "thirddate").compact.map { |date| parse_date(date) }
      end
    end

    def timed?(entry)
      entry["time"].to_s.match?(TIME) || entry["firsttime"].to_s.match?(TIME)
    end

    def time_of(entry, index)
      specific = entry[%w[firsttime secondtime thirdtime][index]] if index < 3
      specific.to_s.match?(TIME) ? specific : entry["time"]
    end

    def parse_date(text)
      day, month, year = text.to_s.match(DATE)&.captures&.map(&:to_i)
      raise "Unparseable PROZESS date: #{text.inspect}" if year.nil?

      Date.new(year, month, day)
    end

    def paragraphs(html)
      html.to_s.split(%r{(?:<br\s*/?>\s*){2,}}i).map { |part| plain(part) }.compact_blank
    end

    def plain(html)
      Nokogiri::HTML.fragment(html.to_s.gsub(%r{<br\s*/?>}i, " ")).text.delete("⁠").squish
    end
  end
end
