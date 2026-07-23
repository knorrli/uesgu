module Scrapers
  class Zent < Agent
    # Restaurant Zent — the bistro-with-stage inside the bimano complex at
    # Zentweg 1A, Bern. The music programme lives on restaurant-zent.ch, not
    # bimano.ch (which is the bouldering/booking side).
    def self.url
      URI.parse("https://restaurant-zent.ch/kulturprogramm")
    end

    def event_rows
      page.css("article.event-item")
    end

    def event_url(row)
      link = row.at_css("a.permalink")
      return if link.blank?

      URI.join("https://restaurant-zent.ch", link.attr("href")).to_s
    end

    # Clean <time>DD.MM.YYYY</time> with the year present (no silent-today risk).
    # The start time never gets its own element — it lives in the body prose
    # ("Start: 18:30", "Türöffnung 18.30") — so mine it with keyword-anchored
    # patterns (see #prose_time). An event whose prose names no time keeps the
    # date-at-midnight default rather than guessing.
    def event_start_time(content)
      date_string = content.at_css("time")&.text&.squish
      raise "Unparseable Zent date: #{date_string.inspect}" unless date_string =~ /\d{1,2}\.\d{1,2}\.\d{4}/

      Time.zone.parse([date_string, prose_time(content.text)].compact.join(" "))
    end

    def event_title(content)
      content.at_css("h2, h1")&.text&.squish
    end

    private

    # The event's start time mined from its body prose, or nil. Keyword-anchored
    # on purpose — a bare \d\d[:.]\d\d would false-match prices ("75.—" survives,
    # but a "18.50" price would not) — and preferring the show start ("Start:",
    # "Beginn") over the doors time ("Türöffnung") when both appear. Both
    # separator styles ("18:30" / "18.30") occur in the wild.
    def prose_time(text)
      match = text.match(/(?:start|beginn|show)\s*:?\s*(?:um\s+)?(\d{1,2})[.:](\d{2})/i) ||
              text.match(/türöffnung\s*:?\s*(?:um\s+)?(\d{1,2})[.:](\d{2})/i)
      return unless match && match[1].to_i < 24 && match[2].to_i < 60

      "#{match[1]}:#{match[2]}"
    end
  end
end
