module Scrapers
  # Helsinki Klub (Zürich-West) publishes its whole programme inline on the
  # homepage (Jimdo, server-rendered). No detail pages, no genres, and the date is
  # split across weekday/day/month divs with NO year — infer it.
  class Helsinki < Agent
    def self.url
      URI.parse("https://www.helsinkiklub.ch/")
    end

    def initialize
      super
      @scrape_date = Date.current
    end

    # The homepage carries no genre/style/tag field (title + support line only),
    # so the scraper collects none. Any genre coverage on these events is
    # incidental — PETZI ships the same shows with tags and a dedup merge / admin
    # pin can leave a few behind. Record a no_field gap.
    field_gaps genres: :no_field

    def event_rows
      page.css("div.event")
    end

    # No per-event URL exists; the block id ("event_1871") is the stable key.
    def event_url(row)
      id = row.attr("id")
      "#{self.class.url}##{id}" if id.present?
    end

    # German weekday/day/month with no year — infer the year as the next
    # occurrence (the page wraps across the year boundary). Start time is free text
    # in `.showtime` ("Bar 19:30 Uhr / Show 20:30 Uhr"); prefer the show time.
    def event_start_time(content)
      day = content.at_css(".date .day")&.text&.squish
      month = month_number(month: content.at_css(".date .month")&.text&.squish)
      raise "Unparseable Helsinki date: #{content.at_css('.date')&.text&.squish.inspect}" if day.blank? || !month.is_a?(Integer)

      hour, minute = show_time(content.at_css(".showtime")&.text.to_s)
      Time.zone.local(year_for(month, day.to_i), month, day.to_i, hour, minute)
    end

    # The headline is the bare text of `.top` (its `.addition` child is a sub-line);
    # header-only nights carry just a `.support` line — fall back to that.
    def event_title(content)
      top = content.at_css(".agenda .top")
      title = top&.children&.select(&:text?)&.map { |n| n.text.squish }&.compact_blank&.join(" ")
      title.presence || content.at_css(".agenda .support")&.text&.squish
    end

    # The support line(s) below the headline. Skip it when the headline itself fell
    # back to the support line (header-only nights — see event_title), otherwise the
    # description would just echo the title.
    def event_description(content)
      support = content.css(".agenda .support").map { |node| node.text.squish }.compact_blank.join(", ").presence
      support unless support == event_title(content)
    end

    # No genre field, but the `.description` blurb names real styles — mine the
    # known ones (Scrapers::Agent match-only mining).
    def event_genre_prose(content)
      content.css(".description p").map(&:text).join("\n")
    end

    private

    # Pick the show start over the bar-open time, tolerating "20:30", "20.30" and
    # bare-hour "21 Uhr". Tokens are joined by non-breaking spaces, so allow any
    # Unicode space separator (\p{Zs}, which includes  ) before "Uhr".
    def show_time(text)
      segment = text[/Show.*/i] || text
      if (m = segment.match(/(\d{1,2})[:.](\d{2})/))
        [m[1].to_i, m[2].to_i]
      elsif (m = segment.match(/(\d{1,2})[\s\p{Zs}]*Uhr/i))
        [m[1].to_i, 0]
      else
        [0, 0]
      end
    end

    def year_for(month, day)
      year = @scrape_date.year
      year += 1 if Date.new(year, month, day) < @scrape_date
      year
    end
  end
end
