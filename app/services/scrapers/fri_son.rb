module Scrapers
  class FriSon < Agent
    def self.location
      'FriSon'
    end

    def self.locations
      [location, 'Fribourg', 'FR']
    end

    def self.url
      URI.parse('https://www.fri-son.ch/fr/programme?f%5B0%5D=category%3A1')
    end

    def event_rows
      page.css('.view-events .node--type-event')
    end

    def event_url(row)
      URI.join(self.class.url, row.at_css('a').attr('href')).to_s
    end

    def event_start_time(content)
      # Take the date as written in the source's datetime attr — NOT to_date of the
      # parsed UTC instant, which rolls to the next local day for late-UTC times in
      # winter (the venue's field-date is a UTC timestamp).
      date = content.css('.field.field--name-field-date .datetime').attr('datetime').to_s[/\d{4}-\d{2}-\d{2}/]
      time_string = content.css('.field.field--name-field-time-doors').text.squish
      Time.zone.parse("#{date}, #{time_string}")
    end

    def event_title(content)
      content.css('.performers.main .performer').children.map do |node|
        next "(#{node.text.squish})" if node.name == 'sup' && node.text.squish.present?
        node.text.squish
      end.compact_blank.join(' ')
    end

    def event_description(content)
      content.css('.performers.standard .performer').map do |node|
        node.children.map  do |child|
          next "(#{child.text.squish})" if child.name == 'sup' && child.text.squish.present?
          child.text.squish
        end.compact_blank.join(' ')
      end.compact_blank.join(', ').presence
    end

    def event_genres(content)
      content.css('.genre-wrapper .field__item').map { |tag| tag.text.squish }
    end
  end
end
