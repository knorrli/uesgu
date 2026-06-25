module Scrapers
  # Café Kairo (Lorraine, Bern) publishes its whole programme inline on one page
  # (no per-event detail pages). Each concert is an <article id="kultur_…"> whose
  # `.concerts_date time` carries a full date + time. The `datetime` attribute's
  # zone offset is wrong (server-misconfigured to a US offset), so read only the
  # local date/time portion and treat it as Swiss wall-clock.
  class Kairo < Agent
    def self.url
      URI.parse("https://www.cafe-kairo.ch/programm")
    end

    # Café Kairo's listing carries an inline blurb but no genre/style/tag field.
    field_gaps genres: :no_field

    def event_rows
      page.css('article[id^="kultur_"]')
    end

    # Non-concert culture posts (exhibitions, info) carry no date block — skip them.
    def skip_row?(row)
      row.at_css(".concerts_date time")&.attr("datetime").blank?
    end

    # No detail page exists; the article id ("kultur_17431") is the stable key.
    def event_url(row)
      "#{self.class.url}##{row.attr('id')}"
    end

    def event_start_time(content)
      stamp = content.at_css(".concerts_date time")&.attr("datetime").to_s
      /(?<y>\d{4})-(?<mo>\d{2})-(?<d>\d{2})T(?<h>\d{2}):(?<mi>\d{2})/ =~ stamp
      raise "Unparseable Kairo date: #{stamp.inspect}" if y.blank?

      Time.zone.local(y.to_i, mo.to_i, d.to_i, h.to_i, mi.to_i)
    end

    def event_title(content)
      content.at_css(".text h2")&.text&.squish
    end

    # The blurb's lead paragraph is the venue's concise secondary line — for concerts
    # an origin+style tagline ("Bern – Cold Wave/Gothic"), elsewhere a short category
    # word. Surface it; the full prose still feeds genre mining via event_genre_prose.
    def event_description(content)
      content.css(".text p").map { |node| node.text.squish }.find(&:present?)
    end

    # No genre field, but the inline blurb (the `.text` prose paragraphs after the
    # `h2.h1` title) names real styles — mine the known ones (Scrapers::Agent
    # match-only mining). The h2 title is excluded; only the `<p>` prose is scanned.
    def event_genre_prose(content)
      content.css(".text p").map(&:text).join("\n")
    end
  end
end
