module Scrapers
  class Docks < Agent
    def self.location
      'Docks'
    end

    def self.locations
      [location, 'Lausanne', 'VD']
    end

    def self.url
      URI.parse('https://www.docks.ch/programme')
    end

    def event_rows
      page.css('.programme-container .mix.concerts')
    end

    def event_url(row)
      URI.parse(link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    def event_start_time(content)
      date_string = content.css('.event-infos .event-info-date').text.squish[/\d{1,2}\.\d{1,2}\.\d{4}/]
      time_string = content.css('.event-infos .event-info-door').last.text.squish[/\d{2}:\d{2}/]
      Time.zone.parse("#{date_string}, #{time_string}")
    end

    def event_title(content)
      content.css('.top-event-container h1').text.squish
    end

    def event_subtitle(content)
      content.css('.event-subtitle').text.split('+').map { |part| part.squish }.compact_blank.join(', ')
    end

    # Consumption-only: Docks has no dedicated genre field (the former
    # `.event-info-style` selector is dead in the current markup). The only
    # genre-ish signal is the per-artist `.artist-info` spans, which interleave
    # the artist's ORIGIN COUNTRY CODE ("US", "CH") with a loose genre word
    # ("ROCK"). Matched against the curated vocabulary, the real genres survive
    # and the origin codes drop out for free (a proper origin facet is future
    # work). Reading it as discovery is what minted "Us"/"Ch" as genres.
    def event_consumption_genres(content)
      content.css('.artist-item .artist-info').map { |node| node.text.squish }.compact_blank.map { |tag| tag.squish.titleize }.uniq.sort
    end

    private

    def link_for(row)
      Page::Link.new(row.at_css('a'), @mech, page)
    end
  end
end
