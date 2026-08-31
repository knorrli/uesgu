module Scrapers
  class Z7 < Agent
    TAG_VOCABULARY_URL = URI.parse("https://z-7.ch/wp-json/wp/v2/product_tag?per_page=100").freeze

    def self.url
      URI.parse("https://z-7.ch/")
    end

    def self.event_url_pattern
      %r{\Ahttps://z-7\.ch/event/}
    end

    def event_rows
      page.css(".block-event-calendar article")
    end

    def skip_row?(row)
      hall = row.at_css("a span")&.text&.squish
      hall.present? && hall.exclude?("Z7")
    end

    def event_url(row)
      URI.join(self.class.url, link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    def event_start_time(content)
      date = current_row.at_css("time")&.[]("datetime")
      raise "Missing Z7 date for #{current_row.at_css('h2')&.text&.squish.inspect}" if date.blank?

      Time.zone.parse([date, meta_value(content, "Beginn")&.[](/\d{1,2}:\d{2}/)].compact.join(" "))
    end

    def event_title(content)
      header(content)&.at_css("h1")&.text&.squish
    end

    def event_description(content)
      header(content)&.css("p, h4")&.map { |node| node.text.squish }&.compact_blank&.join(", ")
    end

    def event_genres(content)
      tag_slugs(content).filter_map { |slug| tag_names[slug] }
    end

    private

    def link_for(row)
      Page::Link.new(row.at_css("a"), @mech, page)
    end

    def header(content)
      content.at_css(".block-event-product-header")
    end

    def tag_slugs(content)
      content.at_css("div[id^=product-]")&.[]("class").to_s.scan(/product_tag-([a-z0-9-]+)/).flatten
    end

    def tag_names
      @tag_names ||= fetch_tag_names
    end

    def fetch_tag_names
      response = get(TAG_VOCABULARY_URL)
      return {} if response.blank?

      parse_json(response.body).to_h { |term| [term["slug"], term["name"]] }
    rescue Mechanize::Error => e
      Rails.logger.error("[#{self.class.location}] tag vocabulary unavailable: #{e.class}: #{e.message}")
      {}
    end

    def meta_value(content, label)
      row = content.css(".fooevents-meta p").find { |p| p.at_css("b")&.text&.squish&.start_with?(label) }
      row&.text&.squish
    end
  end
end
