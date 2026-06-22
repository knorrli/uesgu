module Scrapers
  class Gaskessel < Agent
    def self.location
      'Gaskessel'
    end

    def self.locations
      [location, 'Bern', 'BE']
    end

    def self.url
      URI.parse('https://gaskessel.ch/programm/')
    end

    def event_rows
      page.css('.eventpreview')
    end

    def event_url(row)
      URI.join(self.class.url, row.at_css('a.previewlink').attr('data-url')).to_s
    end

    def event_start_time(content)
      date_string = content.css('.previewlink .eventdatum').text.squish
      time_string = content.css('.infobox .tcell').children.select { |node| node.text.squish =~ /^\d{1,2}:\d{1,2}$/ }.map(&:text).join

      /(?<day>\d{1,2})?\.(?<month>\d{1,2})?\.(?<year>\d+)/ =~ date_string
      /(?<hour>\d{1,2})?:(?<minute>\d{1,2})?/ =~ time_string

      raise "Unparseable date #{date_string.inspect}" if day.blank? || month.blank? || year.blank?

      Time.zone.parse("20#{year}-#{month}-#{day} #{hour}:#{minute}")
    end

    def event_title(content)
      title = content.css('.eventname').text.squish
      title.presence || content.at_css('p').children.map do |node|
        next "(#{node.text.squish})" if node.name == 'sup' && node.text.squish.present?

        node.text.squish
      end.compact_blank.join(' ')
    end

    def event_description(content)
      content.css('.subtitle').text.split(',').map { |part| part.squish }.compact_blank.join(', ')
    end

    def event_genres(content)
      # The venue packs several genres into one comma-separated `.eventgenre` span
      # ("City Pop, Funk, Soul"), so split on commas into atomic genres rather than
      # storing the whole string as a single junk tag. Mirrors event_description.
      content.css('.eventgenre').flat_map { |node| node.text.split(',') }.map(&:squish).compact_blank
    end
  end
end
