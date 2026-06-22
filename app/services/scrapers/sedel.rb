module Scrapers
  class Sedel < Agent
    def self.location
      'Sedel'
    end

    def self.locations
      [location, 'Luzern', 'LU']
    end

    def self.url
      URI.parse('https://sedel.ch')
    end

    def event_rows
      page.css('.programm ul > li')
    end

    def event_url(row)
      URI.join(self.class.url, link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    def event_start_time(content)
      date_string = content.css('time').attr('datetime')
      Time.zone.parse(date_string)
    end

    def event_title(content)
      content.css('.field-name-node-title').text.split(' | ').compact_blank.map(&:squish).join(', ')
    end

    def event_description(content)
      content.css('.field-name-field-veranstalter').text.squish
    end

    def event_genres(content)
      content.css('.field-name-field-stil-taxo').text.split(' | ').compact_blank.map(&:squish)
    end

    private

    def link_for(row)
      Page::Link.new(row.at_css('a'), @mech, page)
    end
  end
end
