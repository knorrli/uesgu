module Scrapers
  class Zent < Agent
    def self.url
      URI.parse("https://restaurant-zent.ch/kulturprogramm")
    end

    def event_rows
      page.css("article.event-item")
    end

    def event_url(row)
      link = row.at_css("a.permalink")
      return if link.blank?

      URI.join("https://restaurant-zent.ch", link.attr("href")).to_s
    end

    def event_start_time(content)
      date_string = content.at_css("time")&.text&.squish
      raise "Unparseable Zent date: #{date_string.inspect}" unless date_string =~ /\d{1,2}\.\d{1,2}\.\d{4}/

      Time.zone.parse([date_string, prose_time(content.text)].compact.join(" "))
    end

    def event_title(content)
      content.at_css("h2, h1")&.text&.squish
    end

    private

    def prose_time(text)
      match = text.match(/(?:start|beginn|show)\s*:?\s*(?:um\s+)?(\d{1,2})[.:](\d{2})/i) ||
              text.match(/türöffnung\s*:?\s*(?:um\s+)?(\d{1,2})[.:](\d{2})/i)
      return unless match && match[1].to_i < 24 && match[2].to_i < 60

      "#{match[1]}:#{match[2]}"
    end
  end
end
