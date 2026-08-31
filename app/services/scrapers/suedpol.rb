module Scrapers
  class Suedpol < Agent
    MUSIC_CATEGORIES = ["Konzert", "Club"].freeze

    field_gaps genres: :no_field, description: :no_field

    Row = Struct.new(:node, :detail, keyword_init: true)

    def self.url
      URI.parse("https://www.sudpol.ch/programm")
    end

    def self.programm_url(year)
      URI.parse("https://www.sudpol.ch/programm?year=#{year}")
    end

    def self.event_url_pattern
      %r{\Ahttps://www\.sudpol\.ch/programm\?event=}
    end

    def event_rows
      nodes = list_nodes(page.body)
      if (resp = get(self.class.programm_url(Date.current.year + 1)))
        nodes.concat(list_nodes(resp.body))
      end
      nodes.select { |node| upcoming?(node) && music?(node) }.map { |node| Row.new(node: node) }
    end

    def event_url(row)
      "https://www.sudpol.ch/programm?event=#{row.node["data-event-alias"]}"
    end

    def event_content(row)
      row.detail = detail_fragment(row.node["data-event-id"])
      row
    end

    def event_start_time(row)
      stamp = row.node["data-date"]
      raise "Missing Südpol date for #{row.node["data-event-alias"].inspect}" if stamp.blank?

      date = Time.zone.at(stamp.to_i).to_date
      time = row.detail&.at_css(".event-item__time")&.text.to_s[/\d{1,2}[:.]\d{2}/]
      Time.zone.parse([date.iso8601, time&.tr(".", ":")].compact.join(" "))
    end

    def event_title(row)
      row.node.at_css(".event-list__title")&.text&.squish
    end

    def event_genre_prose(row)
      row.detail&.at_css(".event-item__body")&.text
    end

    private

    def list_nodes(body)
      Nokogiri::HTML(body).css(".event-list__item").to_a
    end

    def upcoming?(node)
      stamp = node["data-date"]
      stamp.present? && Time.zone.at(stamp.to_i).to_date >= Date.current
    end

    def music?(node)
      categories = node.at_css(".event-list__category")&.text.to_s.split(",").map(&:squish)
      categories.intersect?(MUSIC_CATEGORIES)
    end

    def detail_fragment(event_id)
      resp = get(URI.parse("https://www.sudpol.ch/api/event/#{event_id}"))
      return nil unless resp

      html = parse_json(resp.body, default: {})["content"]
      Nokogiri::HTML.fragment(html) if html.present?
    end
  end
end
