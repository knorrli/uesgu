module Scrapers
  class BadBonn < Agent
    # club.badbonn.ch serves no robots.txt (all hosts 404) but ships a
    # `<meta name="robots" content="noindex, nofollow">` on every page — a
    # CMS/site-builder indexing default, not a crawl ban. Mechanize lumps that
    # meta tag in with robots.txt and raises RobotsDisallowedError, so the only
    # way past it is to opt this venue out of robots enforcement entirely. We
    # still identify honestly and crawl gently (one daily pass).
    self.respect_robots = false

    def self.location
      'Bad Bonn'
    end

    def self.locations
      [location, 'Düdingen', 'FR']
    end

    def self.url
      URI.parse('https://club.badbonn.ch/program')
    end

    # Bad Bonn's pages carry only a title + a free-text blurb (the subtitle) —
    # there is no genre/style/tag field anywhere to extract.
    field_gaps genres: :no_field

    def event_rows
      page.css('.program-row')
    end

    def event_url(row)
      URI.parse(link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    # The detail page carries the event data as data-* attributes on <article>.
    # (The element used to be `article.show`; the site dropped that class in a
    # Tailwind redesign, but the data attributes are stable.)
    def event_start_time(content)
      article = content.at_css('article[data-date]')
      date_string = article&.attr('data-date').to_s
      time_string = article&.attr('data-time').to_s
      raise "Missing date (article[data-date]) on #{content.uri}" if date_string.blank?
      Time.zone.parse("#{date_string}, #{time_string}")
    end

    def event_title(content)
      content.at_css('article[data-date]').attr('data-title').to_s
    end

    def event_subtitle(content)
      content.css('article p').map { |node| node.text.squish }.find(&:present?).to_s
    end

    private

    def link_for(row)
      Page::Link.new(row.at_css('.program-bands a'), @mech, page)
    end
  end
end
