module Scrapers
  class Ono < Agent
    SECTIONS = {
      "sounds" => "Sounds",
      "jazz-2" => "Jazz",
      "klassik-2" => "Klassik",
      "literatur" => "Literatur",
      "tanz-theater" => "Tanz & Theater",
      "literatur-2" => "Spezial"
    }.freeze

    def self.section_url(slug)
      URI.parse("https://www.onobern.ch/#{slug}/")
    end

    def self.url
      section_url(SECTIONS.keys.first)
    end

    field_gaps description: :no_field

    def event_rows
      first_slug, *rest = SECTIONS.keys
      rows = tag_rows(page, SECTIONS[first_slug])
      rest.each do |slug|
        resp = get(self.class.section_url(slug))
        break unless resp

        rows.concat(tag_rows(resp, SECTIONS[slug]))
      end
      rows
    end

    def event_url(content)
      content.at_css('[itemprop="url"]')&.attr("href").presence
    end

    def event_start_time(content)
      date_string = content.at_css('meta[itemprop="startDate"]')&.attr("content")
      raise "Unparseable ONO date: #{date_string.inspect}" if date_string.blank?

      Time.zone.parse(date_string)
    end

    def event_title(content)
      content.at_css(".evcal_event_title")&.text&.squish
    end

    def event_description(content)
      content.at_css(".evcal_event_subtitle")&.text&.squish.presence
    end

    def event_genres(content)
      Array(content["data-ono-genre"].presence)
    end

    def event_cancelled?(_event, content)
      content.at_css('meta[itemprop="eventStatus"]')&.attr("content").to_s.include?("EventCancelled")
    end

    private

    def tag_rows(page, genre)
      page.search("#evcal_list .eventon_list_event").to_a.each do |row|
        row["data-ono-genre"] = genre
      end
    end
  end
end
