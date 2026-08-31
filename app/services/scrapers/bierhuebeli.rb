require "cgi"
require "nokogiri"

module Scrapers
  class Bierhuebeli < Agent
    def self.url
      URI.parse("https://bierhuebeli.ch/wp-json/wp/v2/event?per_page=100")
    end

    def event_rows
      parse_json(page.body)
    end

    def skip_row?(row)
      event_field(row, "datum").blank?
    end

    def event_url(row)
      row["link"].to_s
    end

    def event_start_time(row)
      stamp = event_field(row, "datum")
      raise "Unparseable Bierhübeli date: #{stamp.inspect}" if stamp.blank?

      t = Time.at(stamp.to_i).utc
      Time.zone.local(t.year, t.month, t.day, t.hour, t.min)
    end

    def event_title(row)
      CGI.unescapeHTML(row.dig("title", "rendered").to_s).squish
    end

    def event_description(row)
      html = event_field(row, "billboard-byline").to_s.gsub(%r{<br\s*/?>}i, " · ")
      CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(html)).squish.presence
    end

    def event_genres(row)
      extract_tag_genres(row)
    end

    def event_genre_prose(row)
      musicradar_stil_text(row)
    end

    private

    def event_field(row, key)
      row.dig("toolset-meta", "eventzusatz", key, "raw")
    end

    def artist_field(row, key)
      row.dig("toolset-meta", "artistfields", key, "raw").to_s.squish
    end

    def extract_tag_genres(row)
      %w[beschreibungstag-1 beschreibungstag-2 beschreibungstag-3].filter_map do |key|
        artist_field(row, key).presence
      end
    end

    def musicradar_stil_text(row)
      doc   = Nokogiri::HTML.fragment(artist_field(row, "musicradar"))
      label = doc.css("strong").find { |s| s.text.squish =~ /\AStil:?\z/i }
      return "" unless label

      parts, node = [], label.next_sibling
      while node && !(node.element? && node.name == "strong")
        parts << node.text if node.text?
        node = node.next_sibling
      end
      parts.join(" ").squish
    end
  end
end
