module Scrapers
  class Sedel < Agent
    def self.url
      URI.parse("https://sedel.ch")
    end

    def event_rows
      page.css(".programm ul > li")
    end

    def event_url(row)
      URI.join(self.class.url, link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    def event_start_time(content)
      date_string = content.css("time").attr("datetime")
      Time.zone.parse(date_string)
    end

    def event_title(content)
      content.css(".field-name-node-title").text.split(" | ").compact_blank.map(&:squish).join(", ")
    end

    def event_description(content)
      content.css(".field-name-field-veranstalter").text.squish
    end

    # The style field is a Drupal entity reference, but the venue's terms are
    # themselves combined strings ("Crustpunk Hardcore / Speed Metal D-Beat Punk",
    # "Darkmetal | Blackmetal", "Punkrock/Folk") — split each term on the
    # separators the source actually uses ("/" and "|", spaced or not). NOT on
    # whitespace: multi-word genres ("Speed Metal", "Punk Rock") are legitimate
    # single tokens, and hyphens ("D-Punk", "Garage-Punk-n-Roll") stay intact.
    def event_genres(content)
      content.css(".field-name-field-stil-taxo .field-item")
             .flat_map { |item| item.text.split(%r{[/|]}) }
             .map(&:squish).compact_blank
    end

    private

    def link_for(row)
      Page::Link.new(row.at_css("a"), @mech, page)
    end
  end
end
