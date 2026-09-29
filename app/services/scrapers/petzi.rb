require "nokogiri"

module Scrapers
  class Petzi < Agent
    self.opens_event_pages = true

    def self.venues
      Venue.all.each_with_object({}) do |venue, map|
        Array(venue.aliases["petzi"]).each { |slug| map[slug] = venue.place_tuple }
      end
    end

    def self.domains
      Venue.all.each_with_object({}) do |venue, map|
        Array(venue.aliases["petzi"]).each { |slug| map[slug] = venue.domain }
      end
    end

    def self.venue_domains = domains.values

    def self.url
      URI.parse("https://www.petzi.ch/en/sitemap.xml")
    end

    def self.location
      "PETZI"
    end

    def self.locations
      [location]
    end

    def self.aggregator?
      true
    end

    def self.homepage?(url)
      uri = URI(url)
      segments = uri.path.split("/").compact_blank
      segments.shift if segments.first&.match?(/\A[a-z]{2}\z/)
      segments.empty? && uri.query.blank?
    rescue URI::InvalidURIError
      false
    end

    def event_rows
      xml = Nokogiri::XML(page.body)
      xml.remove_namespaces!
      xml.css("loc").map(&:text).select { |u| u.include?("/events/") && venue_for(u) }.uniq
    end

    def event_url(row) = known_urls[row] || venue_url(detail_page(row), row) || row

    def event_content(row) = detail_page(row)

    TITLE_DATE = %r{\A(?<day>\d{2})\.(?<month>\d{2})(?:\.(?<year>\d{4})|-\d{2}\.(?<end_month>\d{2})\.(?<end_year>\d{4}))\z}

    def event_start_time(content)
      date = title_parts(content).lazy.filter_map { |p| TITLE_DATE.match(p) }.first
      raise "Unparseable PETZI date for #{current_row}" unless date

      hour, minute = show_or_doors(content)
      Time.zone.local(start_year(date), date[:month].to_i, date[:day].to_i, hour, minute)
    end

    def event_title(content)
      squish(content.parser.at_css("h1")&.text)
    end

    def event_genres(content)
      content.parser.css("a.tag").map { |a| squish(a.text) }.reject(&:blank?).uniq
    end

    def event_description(content)
      paragraphs = description_paragraphs(content)
      pick = support_line(paragraphs) || tagline(paragraphs.first)
      pick if pick && pick.length <= DESCRIPTION_MAX && !same_text?(pick, event_title(content))
    end

    def event_genre_prose(content)
      content.parser.css(".events__details .text_block").flat_map { |block| block.xpath(".//text()").map(&:text) }.join("\n")
    end

    def event_locations(_content)
      venue_for(current_row)
    end

    def postprocess(event)
      event.aggregator_url = current_row
    end

    DESCRIPTION_MAX = 120
    TAGLINE_LINES = 2
    LANGUAGE_TAG = /\A(?:FR|DE|EN)\s*:\s*/
    SUPPORT_LABEL = /\A(?:support|special guests?)\b/i
    LOGISTICS = %r{
      https?://|prix|preis|chf|gib/donne|eintritt|türöffnung|konzertbeginn|abendkasse|
      billet|ticket|sold\s*out|ausverkauft|\bcomplet\b|resale|préventes|prélocation|portes|(?:â|a)ge\s+minimum|minimum\s+age|\d{1,2}\.\d{1,2}\.\d{2,4}
    }xi

    private

    def description_paragraphs(content)
      text = content.parser.css(".events__details .text_block").map { |block| text_with_breaks(block) }.join("\n\n")
      text.unicode_normalize(:nfkc).split(/\n\s*\n/).filter_map do |paragraph|
        paragraph.split("\n").map { |line| squish(line).sub(LANGUAGE_TAG, "") }.reject { |line| logistics?(line) }.join("\n").presence
      end
    end

    def support_line(paragraphs)
      label, *acts = paragraphs.find { |p| p.match?(SUPPORT_LABEL) }&.lines(chomp: true)
      return label if label.nil? || acts.empty?

      "#{label.delete_suffix(':').strip}: #{acts.join(', ')}"
    end

    def tagline(paragraph)
      paragraph if paragraph && paragraph.lines.size <= TAGLINE_LINES
    end

    def text_with_breaks(block)
      block.xpath(".//text()|.//br").map { |node| node.name == "br" ? "\n" : node.text.tr("\n", " ") }.join
    end

    def logistics?(line) = line.match?(LOGISTICS) || !line.match?(/[[:alnum:]]/)

    def same_text?(a, b) = a.downcase.gsub(/[^[:alnum:]]/, "") == b.downcase.gsub(/[^[:alnum:]]/, "")

    def squish(str) = str.to_s.gsub(/\s+/, " ").strip

    def title_parts(content)
      squish(content.parser.at_css("title")&.text).split(" / ")
    end

    def start_year(date)
      return date[:year].to_i if date[:year]

      crosses_new_year = date[:month].to_i > date[:end_month].to_i
      date[:end_year].to_i - (crosses_new_year ? 1 : 0)
    end

    def show_or_doors(content)
      body = squish(content.parser.text)
      time = body[/Event starts at:\s*(\d{1,2})[:.](\d{2})/i, 0] ||
             body[/Doors open at:\s*(\d{1,2})[:.](\d{2})/i, 0]
      return [0, 0] unless time

      m = time.match(/(\d{1,2})[:.](\d{2})/)
      [m[1].to_i, m[2].to_i]
    end

    def known_urls
      @known_urls ||= Event.where.not(aggregator_url: nil).pluck(:aggregator_url, :url).to_h
    end

    def detail_page(row)
      if @detail_row != row
        @detail_row  = row
        @detail_page = get(row)
      end
      @detail_page
    end

    def venue_url(page, row)
      domain = self.class.domains[slug_for(row)]
      return if domain.blank?

      page.links.filter_map(&:href)
          .find { |href| href.start_with?("http") && Scrapers::Discovery.domain(href) == domain && !self.class.homepage?(href) }
    end

    def slug_for(url)
      self.class.venues.keys.find { |s| url =~ %r{/events/\d+-#{Regexp.escape(s)}-} }
    end

    def venue_for(url) = self.class.venues[slug_for(url)]
  end
end
