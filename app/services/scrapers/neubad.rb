module Scrapers
  class Neubad < Agent
    def self.url
      URI.parse("https://neubad.org/veranstaltungen")
    end

    # Music-relevant categories at this mixed-use venue (the rest is film, markets,
    # talks, yoga…). The category sits on the list row as `span.kategorie`.
    MUSIC_CATEGORIES = %w[Konzert Klubnacht].freeze

    # Neubad exposes no music-genre field — its only taxonomy is the event TYPE
    # (`span.kategorie`, mirrored in the detail "Was" row: Konzert, Klubnacht,
    # Kunst, Film…), which we use to filter to music, not to tag a genre. Any
    # genre coverage on these events is incidental (PETZI carries the same shows
    # with tags; a dedup merge or admin pin can leave a few). Record a no_field
    # gap so the low number isn't re-investigated.
    field_gaps genres: :no_field

    def event_rows
      page.css("ul.liste li.zeile")
    end

    def skip_row?(row)
      MUSIC_CATEGORIES.exclude?(row.at_css("span.kategorie")&.text&.squish)
    end

    def event_url(row)
      link = row.at_css(".views-field-title a")
      return if link.blank?

      URI.join("https://neubad.org", link.attr("href")).to_s
    end

    # The list groups events under a year-less <h3> date header; the detail page's
    # "Wann" row gives the full German date WITH the year, so click through for it.
    def event_content(row)
      click(Page::Link.new(row.at_css(".views-field-title a"), @mech, page))
    end

    def event_start_time(content)
      date_string = detail_value(content, "Wann")
      /(?<day>\d{1,2})\.\s*(?<month>\p{L}+)\s+(?<year>\d{4})/ =~ date_string.to_s
      raise "Unparseable Neubad date: #{date_string.inspect}" if day.blank? || month.blank? || year.blank?

      time_string = detail_value(content, "Beginn").to_s[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{year}-#{month_number(month: month)}-#{day} #{time_string}")
    end

    def event_title(content)
      content.at_css("h2.page-title")&.text&.squish
    end

    private

    # Read a labelled value from the detail page's `.event-details` rows
    # (Wann / Was / Wo / Türöffnung / Beginn).
    def detail_value(content, label)
      content.css(".event-details .event-detail-row").each do |row|
        return row.at_css(".event-detail-value")&.text&.squish if row.at_css(".event-detail-label")&.text&.squish == label
      end
      nil
    end
  end
end
