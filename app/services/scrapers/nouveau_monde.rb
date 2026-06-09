module Scrapers
  class NouveauMonde < Agent
    def self.location
      'Nouveau Monde'
    end

    def self.locations
      [location, 'Fribourg', 'FR']
    end

    def self.url
      URI.parse('https://www.nouveaumonde.ch/agenda/')
    end

    def event_rows
      page.css('.poster[data-tofilter*=concert]')
    end

    def event_url(row)
      URI.join(self.class.url, link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    def event_start_time(content)
      date_string = content.css('#section-schedule').children.first.text.squish[/\d{1,2}\.\d{1,2}\.\d{4}/]
      time_string = content.css('#section-schedule .scheduleLine').find { |node| node.text.squish.starts_with?(/Beginn|Debut/) }.text.squish[/\d{1,2}h\d{1,2}/]
      raise "Unparseable date #{content.css('#section-schedule').children.first.text.squish.inspect}" if date_string.blank?
      Time.zone.parse("#{date_string}, #{time_string}")
    end

    def event_title(content)
      content.css('.groupIntro').map do |node|
        country_code = node.css('.plateMedium').text.squish
        act_name = StringIO.new
        act_name << node.children.find { |child| child.name == 'h2' }.text
        act_name << " (#{country_code})" if country_code.present?
        act_name.string
      end.compact_blank.join(', ')
    end

    def event_genres(content)
      main_tags = content.css('.plateSmall').map { |node| node.text.squish }
      artist_tags = content.css('.groupIntro .genTexArea h5').flat_map { |node| node.text.split(/,|\s\-\s|\s[au]nd\s|&|\//) }.map(&:squish).compact_blank
      (main_tags | artist_tags).sort
    end

    private

    def link_for(row)
      Page::Link.new(row, @mech, page)
    end
  end
end
