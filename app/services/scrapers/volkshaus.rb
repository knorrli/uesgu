module Scrapers
  class Volkshaus < Agent
    def self.location
      'Volkshaus Basel'
    end

    def self.locations
      [location, 'Basel', 'BS']
    end

    def self.url
      URI.parse('https://volkshaus-basel.ch/programm/')
    end

    # Volkshaus Basel carries an inline collapse-panel blurb but no genre/style/tag
    # field.
    field_gaps genres: :no_field

    # One server-rendered row per event; the body is an inline collapse panel, so
    # there is no detail page to fetch.
    def event_rows
      page.css('#programmliste .tableitem.event')
    end

    # The venue mixes concerts, talks (vortraege), dance and Oktoberfest — the
    # genre is encoded as a `genre-*` class; keep only music.
    def skip_row?(row)
      !row.classes.include?('genre-musik')
    end

    # No detail URL exists; the per-event anchor targets the inline panel
    # (`#event<id>`), which is stable and unique enough to key the event on.
    def event_url(row)
      anchor = row.at_css('a.toggle-link')&.attr('href')
      return if anchor.blank?

      URI.join(self.class.url, anchor).to_s
    end

    def event_start_time(content)
      cell = content.at_css('.col-sm-3')&.text.to_s
      date_string = cell[%r{\d{1,2}\.\d{1,2}\.\d{4}}]
      raise "Unparseable Volkshaus date: #{cell.squish.inspect}" if date_string.blank?

      time_string = cell[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{date_string} #{time_string}")
    end

    def event_title(content)
      content.at_css('a.toggle-link h4')&.text&.squish
    end

    # The collapse panel's lead paragraph is a concise blurb describing the act/show;
    # surface it as the secondary line. The later panel paragraphs (date, organiser,
    # ticket lines) are noise here but still feed genre mining via event_genre_prose.
    def event_description(content)
      content.css('.panel-collapse .col-sm-8 p').map { |node| node.text.squish }.find(&:present?)
    end

    # No genre field, but the inline collapse-panel blurb names real styles — mine
    # the known ones (Scrapers::Agent match-only mining). The panel mixes the prose
    # with date/organiser lines; match-only over the known vocabulary filters those.
    def event_genre_prose(content)
      content.css('.panel-collapse .col-sm-8 p').map(&:text).join("\n")
    end
  end
end
