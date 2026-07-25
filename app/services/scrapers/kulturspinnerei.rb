require "cgi"
require "nokogiri"

module Scrapers
  # Kulturspinnerei (Bern) runs WordPress + "The Events Calendar" (Modern Tribe).
  # Its public /events/ page renders nothing when the programme is empty, but the
  # plugin's REST API exposes the `event` post type cleanly as JSON — so we read
  # that rather than the DOM. Each row is a Hash.
  #
  # The API filters to upcoming events server-side (its `start_date` defaults to
  # "now"), so we do NOT date-filter in Ruby — the feed already returns only
  # today-or-later shows. per_page=50 comfortably covers this single venue's
  # programme, so one page suffices (no cursor to follow).
  class Kulturspinnerei < Agent
    def self.url
      URI.parse("https://kulturspinnerei.ch/wp-json/tribe/events/v1/events?per_page=50")
    end

    # The Events Calendar exposes `categories` and `tags` per event, but the venue
    # populates neither — every event (2019→2026) ships them empty. Declared dormant
    # (the field exists in the feed but the source never fills it) rather than
    # no_field, so the coverage page's reality-wins rule surfaces a live % the moment
    # they start categorising. Genres today come only from mining the description
    # prose (event_genre_prose), which mints nothing.
    field_gaps genres: :dormant

    def event_rows
      Array(parse_json(page.body)["events"])
    end

    def event_url(row)
      row["url"].to_s
    end

    # `start_date` is the Swiss wall-clock start in "YYYY-MM-DD HH:MM:SS" (no zone),
    # so map it straight onto the zone. `all_day` events carry a placeholder time
    # (e.g. 08:00) we keep as-is — the venue's real programme is timed.
    def event_start_time(row)
      stamp = row["start_date"].to_s
      raise "Unparseable Kulturspinnerei date: #{stamp.inspect}" if stamp.blank?

      Time.zone.parse(stamp)
    end

    def event_title(row)
      CGI.unescapeHTML(row["title"].to_s).squish
    end

    # `description` is HTML prose (artist blurb + door times + a "Zu den Tickets"
    # link). Promote block boundaries to separators so the text doesn't fuse words
    # across paragraphs, then take the fragment's text — Nokogiri decodes every
    # entity (numeric AND named like &nbsp;, which CGI.unescapeHTML leaves behind);
    # squish then collapses the decoded non-breaking spaces too. The feed clamps
    # this to a few lines in the UI.
    def event_description(row)
      html = row["description"].to_s.gsub(%r{</p>|</h3>|<br\s*/?>}i, " · ")
      Nokogiri::HTML.fragment(html).text.squish.presence
    end

    # The structured `categories`/`tags` fields (currently always empty — see the
    # field_gaps note). Kept so genres wake up automatically if the venue ever
    # starts categorising; today this yields nothing and genres come from the
    # description miner below.
    def event_genres(row)
      (Array(row["categories"]) + Array(row["tags"])).filter_map { |t| t["name"].presence }
    end

    # No genre field is populated, but the description prose reliably names real,
    # matchable styles ("…verschiedenartigem Rock…"). Hand the stripped text to the
    # match-only miner: it attaches genres the taxonomy already knows and mints
    # nothing, so a non-genre clause never sticks.
    def event_genre_prose(row)
      event_description(row)
    end
  end
end
