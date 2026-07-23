module Scrapers
  # Südpol (Luzern/Kriens) relaunched in summer 2026 from a headless-WordPress
  # Nuxt SPA to a server-rendered Contao site. The old cms.sudpol.ch REST feed
  # host now serves a hosting-provider default page and every old
  # /programm/<slug>/ permalink 404s (see the stale-row migration that
  # accompanied this rewrite).
  #
  # The public /programm page renders the FULL current year server-side — each
  # event is one `.event-list__item` carrying a stable alias (the deep-link
  # key), its categories, its title, and a `data-date` UNIX stamp that is only
  # MIDNIGHT of the event day. The real start time lives one JSON fetch away on
  # /api/event/<id> (allowed by robots.txt, which blocks only /contao/), whose
  # `content` is the structured detail markup (.event-item__time etc.).
  class Suedpol < Agent
    # The house also programmes theatre/dance/podcasts; these categories are the
    # music slice (the relaunch dropped the old Konzert=4/Club=13/Sound=63 WP
    # term ids). A row can carry several ("Konzert, Sommer im Südpol") — one
    # music category is enough to keep it.
    MUSIC_CATEGORIES = ["Konzert", "Club"].freeze

    # The categories are event TYPES for the site's own filter, not genres, and
    # the relaunch dropped the old free-text tags field — nothing to mint. The
    # detail body prose still names real styles, so mining stays (match-only,
    # see #event_genre_prose). No subtitle field either: the detail is meta rows
    # (date/time/price) plus long body prose, which is not a secondary-text line
    # (the PETZI precedent).
    field_gaps genres: :no_field, description: :no_field

    # One list row plus its lazily-fetched structured detail (nil when the
    # detail API is unavailable — e.g. the offline golden harness).
    Row = Struct.new(:node, :detail, keyword_init: true)

    def self.url
      URI.parse("https://www.sudpol.ch/programm")
    end

    def self.programm_url(year)
      URI.parse("https://www.sudpol.ch/programm?year=#{year}")
    end

    # URLs are built from the alias, so pin the full deep-link shape.
    def self.event_url_pattern
      %r{\Ahttps://www\.sudpol\.ch/programm\?event=}
    end

    # The base fetched /programm (the current year, past months included);
    # fetch next year's page too — around the turn of the year the upcoming
    # programme spans both. Keep only upcoming music rows. A nil `get` (offline
    # golden harness) skips the second year, keeping the golden deterministic.
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

    # Fetch the structured detail once per event; the extractors below read the
    # list row and fall back gracefully when the detail is unavailable.
    def event_content(row)
      row.detail = detail_fragment(row.node["data-event-id"])
      row
    end

    # `data-date` is midnight of the event day — the start TIME only exists in
    # the detail's .event-item__time ("19:00 Uhr"). Without a reachable detail
    # the event keeps the date-at-midnight default rather than guessing.
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

    # The detail body names real styles in its prose ("… zwischen Techno und
    # Volksmusik …"); mine the known ones (match-only; mints nothing).
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

    # The row's categories ("Konzert, Sommer im Südpol") against the music slice.
    def music?(node)
      categories = node.at_css(".event-list__category")&.text.to_s.split(",").map(&:squish)
      categories.intersect?(MUSIC_CATEGORIES)
    end

    # The /api/event/<id> JSON's `content` as a parseable fragment, or nil when
    # the API is unreachable (offline harness) or returns no content.
    def detail_fragment(event_id)
      resp = get(URI.parse("https://www.sudpol.ch/api/event/#{event_id}"))
      return nil unless resp

      html = parse_json(resp.body, default: {})["content"]
      Nokogiri::HTML.fragment(html) if html.present?
    end
  end
end
