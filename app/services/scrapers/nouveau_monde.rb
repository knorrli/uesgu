module Scrapers
  class NouveauMonde < Agent
    def self.url
      URI.parse("https://www.nouveaumonde.ch/agenda/")
    end

    # Nouveau Monde's only taxonomy is activity-type filters (concert / expo /
    # atelier / …), not music genres — there is no genre/style field to extract.
    field_gaps genres: :no_field

    def event_rows
      page.css(".poster[data-tofilter*=concert]")
    end

    def event_url(row)
      URI.join(self.class.url, link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    def event_start_time(content)
      schedule = content.css("#section-schedule")
      date_string = schedule.children.first.text.squish[/\d{1,2}\.\d{1,2}\.\d{4}/]
      raise "Unparseable date #{schedule.children.first.text.squish.inspect}" if date_string.blank?

      time_node = schedule.css(".scheduleLine").find { |node| node.text.squish.match?(/\d{1,2}h\d{1,2}/) }
      time_string = time_node&.text&.squish&.slice(/\d{1,2}h\d{1,2}/)
      Time.zone.parse([date_string, time_string].compact.join(", "))
    end

    def event_title(content)
      # Some events render multiple `.groupHeading` sections (the lineup acts
      # each get one, doubling as `.groupIntro`); only the first carries the
      # event title — taking all of them jams the artist names onto the title.
      content.at_css(".groupHeading h2")&.text&.squish
    end

    def event_description(content)
      content.css(".groupIntro").map do |node|
        country_code = node.css(".plateMedium").text.squish
        act_name = StringIO.new
        act_name << node.children.find { |child| child.name == "h2" }.text
        act_name << " (#{country_code})" if country_code.present?
        act_name.string
      end.compact_blank.join(", ")
    end

    # No genre extraction: the live ProcessWire template exposes no genre/style
    # field (verified against the live site 2026-06-12). Both former selectors
    # were dead — `.plateSmall` no longer exists and the lone `<h5>` is the
    # event-info header, not genres. The only genre-ish text is artist-reference
    # prose ("For fans of : Daughter…") and the bio, which we deliberately don't
    # mine. So Nouveau Monde is a genre-less venue (inherits the nil default).
    # (The list/event selectors still work — only genres are absent.)

    private

    def link_for(row)
      Page::Link.new(row, @mech, page)
    end
  end
end
