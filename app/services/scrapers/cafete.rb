module Scrapers
  # Cafete (the Cafeteria/"Kafi" in Bern's Reitschule) publishes its whole club
  # programme inline on a hand-built static homepage — one `.event` block per
  # night, server-rendered, no CMS, no detail pages. It carries a clean `.style`
  # genre line ("Style: Techno / Progressive House"), a `.description` blurb, and a
  # German date+time line with a full year, so there's nothing JS-hydrated to chase
  # and no year to infer.
  #
  # No per-event URL exists (no anchors, no block ids), so we synthesize a stable
  # key from the date line — the venue lists at most one night per date+time, and
  # that text is invariant across re-scrapes, so it dedups cleanly. A non-event
  # notice (Sommerpause banner) lives in a `.info` div, not `.event`, so it's never
  # picked up.
  class Cafete < Agent
    def self.url
      URI.parse("https://cafete.ch/")
    end

    def event_rows
      page.css(".event")
    end

    # No anchor/id on the blocks — the date line is the stable, unique key
    # (invariant across re-scrapes; one night per date+time).
    def event_url(row)
      key = row.at_css(".date")&.text&.parameterize
      "#{self.class.url}##{key}" if key.present?
    end

    # "Do. 09. Juli 2026 — 23:30": weekday prefix, then day/month/year and a time.
    # The em-dash separator (an unterminated `&#8212` entity in the source) is
    # irrelevant — we pull the fields out by shape and ignore everything between.
    def event_start_time(content)
      date_line = content.at_css(".date")&.text.to_s
      /(?<day>\d{1,2})\.\s*(?<month>\p{L}+)\s+(?<year>\d{4})/ =~ date_line
      time = date_line[/\d{1,2}:\d{2}/]
      raise "Unparseable Cafete date: #{date_line.inspect}" if day.blank? || month.blank? || year.blank?

      Time.zone.parse("#{year}-#{month_number(month: month)}-#{day} #{time}")
    end

    def event_title(content)
      content.at_css(".title")&.text&.squish
    end

    def event_description(content)
      content.at_css(".description")&.text&.squish.presence
    end

    # The `.style` line is the venue's own genre field, prefixed "Style:" and
    # slash-separated ("Techno / Progressive House").
    def event_genres(content)
      content.at_css(".style")&.text.to_s
             .sub(/\A\s*Style:\s*/i, "")
             .split("/").map(&:squish).compact_blank
    end
  end
end
