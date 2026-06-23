module Scrapers
  class Kiff < Agent
    def self.location
      "KIFF"
    end

    def self.locations
      [location, "Aarau", "AG"]
    end

    def self.url
      URI.parse("https://www.kiff.ch/programm")
    end

    def event_rows
      page.css(".FilterPage__FilterResults > .Card-Event")
    end

    def event_url(row)
      URI.parse(link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    # The start time lives on the list card, not the detail page, so read it from
    # the current row rather than the clicked-into content.
    def event_start_time(_content)
      Time.zone.parse(current_row.css(".Card__Date time").attr("datetime"))
    end

    def event_title(content)
      content.css(".EventPage__Subtitle h2").children.map do |node|
        next "," if node.name == "br"
        next "(#{node.text.squish})" if node["class"] == "Act__country-code" && node.text.squish.present?

        node.text.squish
      end.compact_blank.join(" ")
    end

    def event_description(content)
      content.css(".EventPage__SupportActs").children.map do |node|
        next if node.text.squish.blank?

        act_list = node.css(".Act").map do |act|
          country_code = act.css(".Act__country-code").text.squish
          act_name = StringIO.new
          act_name << act.css(".Act__name").text.squish
          act_name << " (#{country_code})" if country_code.present?
          act_name.string.presence || act.text
        end.compact_blank.join(", ")

        "#{node.css('dt').text.squish}: #{act_list}".presence || node.text
      end.compact_blank.join("\n").presence
    end

    def event_genres(content)
      content.css(".EventPage__Tags").children.map { |node| node.text.squish }.compact_blank
    end

    private

    def link_for(row)
      Page::Link.new(row.at_css(".Card__Link"), @mech, page)
    end
  end
end
