module Scrapers
  class Schueuer < Agent
    def self.location
      'Schüür'
    end

    def self.locations
      [location, 'Luzern', 'LU']
    end

    def self.url
      URI.parse('https://www.schuur.ch/programm')
    end

    def event_rows
      page.css('.viz-event-list-box')
    end

    def event_url(row)
      URI.parse(row.at_css('a.viz-event-box-details-link').attr('href').to_s).to_s
    end

    # Skip (and warn about) any row whose date we can't parse into a real time,
    # so one festival multi-day banner or a "Diverse Daten" placeholder doesn't
    # take the rest of Schüür's programme down with it. The parse itself lives in
    # #parse_start_time; here we just probe it and log the offending text at warn.
    def skip_row?(row)
      raw = date_text(row)
      return false if parse_start_time(raw)

      Rails.logger.warn(
        "[#{self.class.location}] Skipping event with unparseable date #{raw.inspect}"
      )
      true
    end

    def event_start_time(content)
      parse_start_time(date_text(content))
    end

    def event_title(content)
      content.css('.viz-event-name').text.squish
    end

    def event_subtitle(content)
      content.css('.viz-event-headline').text.squish
    end

    def event_genres(content)
      content.css('.viz-event-genre').map { |node| node.text.squish }
    end

    private

    def date_text(node)
      node.css('.viz-event-date').text.squish
    end

    # Parse Schüür's date string into a Time, or return nil when it can't be
    # made into a real date (so #skip_row? can warn-and-skip instead of the run
    # aborting on an ArgumentError).
    #
    # The site mostly emits "Do. 11. Juni 2026 – 21:00", but a few rows are
    # multi-day ranges ("Fr. 11. – So. 13. Juni 2026 – 20:00", "11.–13. Juli
    # 2026") and the occasional placeholder ("Diverse Daten"). The old single
    # regex grabbed the FIRST `\d+.` as the day but then captured the range's
    # trailing weekday/day as the "month" and lost the year — yielding either a
    # bogus month word or a day/month that blew up Time.zone.parse with
    # "argument out of range". We instead pull each field with its own anchored
    # pattern: the FIRST day number, the German MONTH WORD (a known month name,
    # not just the next token), and the 4-digit YEAR wherever they sit, so a
    # leading day-range no longer derails the month/year. A start day-of-month
    # is enough; we take the range's first day.
    def parse_start_time(text)
      return nil if text.blank?

      # The FIRST "<n>." is the (start) day; for a multi-day range we keep its
      # start, ignoring the range's trailing day.
      day   = text[/\b(\d{1,2})\./, 1]
      month = text[MONTH_WORD]
      year  = text[/\b(\d{4})\b/, 1]
      return nil if day.blank? || month.blank? || year.blank?

      text =~ /(?<hour>\d{1,2}):(?<minute>\d{1,2})/
      hour   = Regexp.last_match&.named_captures&.dig('hour')
      minute = Regexp.last_match&.named_captures&.dig('minute')

      Time.zone.parse("#{year}-#{month_number(month: month)}-#{day}, #{hour}:#{minute}")
    rescue ArgumentError
      # Day/month still out of range despite passing the field checks (e.g. a
      # garbled "32. Juni"): treat as unparseable rather than aborting the run.
      nil
    end

    # The German month words Schüür uses, matched as whole words so a range's
    # weekday/day token can't masquerade as the month.
    MONTH_WORD = /
      \b(?:
        Jan(?:uar)? | Feb(?:ruar)? | M(?:är|rz|ärz) | Apr(?:il)? | Mai
        | Jun[i]? | Jul[i]? | Aug(?:ust)? | Sept?(?:ember)? | Okt(?:ober)?
        | Nov(?:ember)? | Dez(?:ember)?
      )\b
    /x
  end
end
