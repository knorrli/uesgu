module Scrapers
  # Mühle Hunziken (Rubigen, BE) lists its programme as <li> rows whose detail
  # link carries the full ISO date in its slug (…-2026-06-15). The list shows no
  # start time, so click into the detail page for the "Showbeginn" time. Title and
  # date come from the list row; only the time needs the detail fetch.
  class MuehleHunziken < Agent
    DATE_SLUG = /-(?<y>\d{4})-(?<mo>\d{2})-(?<d>\d{2})\z/

    def self.location
      "Mühle Hunziken"
    end

    def self.locations
      [location, "Rubigen", "BE"]
    end

    def self.url
      URI.parse("https://muehlehunziken.ch/programm")
    end

    def event_rows
      page.css("li.wavy-bottom")
    end

    # Undated rows are category/section links (festivals, info), not datable
    # concerts — skip anything whose link slug doesn't end in an ISO date.
    def skip_row?(row)
      row_href(row).to_s !~ DATE_SLUG
    end

    def event_url(row)
      row_href(row)
    end

    # SHAPE_B: the detail page carries the only start time ("Showbeginn").
    def event_content(row)
      click(link_for(row))
    end

    # Date from the list-row slug (stable, year-qualified); time from the detail's
    # Showbeginn (falling back to door time), written German-style as "20.00".
    def event_start_time(content)
      date = row_href(current_row).match(DATE_SLUG)
      raise "Unparseable Mühle date: #{row_href(current_row).inspect}" if date.nil?

      hour, minute = show_time(content)
      Time.zone.local(date[:y].to_i, date[:mo].to_i, date[:d].to_i, hour, minute)
    end

    def event_title(content)
      current_row.at_css("h2")&.text&.squish
    end

    # A secondary line under the title in the list row — a support act
    # ("& Annika Strand"), an afterparty/festival note, or a "next shows"
    # pointer. Optional: only some events carry one. It's the row's small
    # heading-slot <div> (the only `text-sm md:text-xl` block), styled apart from
    # the <h2> title — read from the list row like the title (the detail click is
    # only ever for the start time).
    def event_description(_content)
      div = current_row.css("div").find do |node|
        classes = node["class"].to_s
        classes.include?("text-sm") && classes.include?("md:text-xl")
      end
      div&.text&.squish.presence
    end

    # The detail page carries a venue-typed genre bar (beside a language badge and
    # Spotify link) with no usable wrapper class — just bare text nodes joined by
    # `<span class="last-of-type:hidden">, </span>` comma separators, which are the
    # page's only such inline comma-list. So anchor on those separators, read their
    # parent, and split on the commas they carry. Third-party free-text that
    # sometimes holds a non-genre category ("Podcast"); those tokens mint and are
    # blocked downstream rather than gated at ingest.
    def event_genres(content)
      list = content.css("span").find { |s| s["class"].to_s.include?("last-of-type:hidden") }&.parent
      return [] unless list

      list.text.split(",").map(&:squish).reject(&:blank?)
    end

    private

    def row_href(row)
      row&.at_css("a")&.attr("href").to_s
    end

    def link_for(row)
      Page::Link.new(row.at_css("a"), @mech, page)
    end

    # Definition list: <dt>Showbeginn</dt><dd>20.00</dd>. Prefer the show start,
    # fall back to door time, then to midnight if neither is published.
    def show_time(content)
      %w[Showbeginn Beginn Türöffnung Einlass].each do |label|
        dt = content.css("dt").find { |n| n.text.squish.start_with?(label) }
        time = dt&.at_xpath("following-sibling::dd[1]")&.text.to_s[/\d{1,2}[.:]\d{2}/]
        return time.split(/[.:]/).map(&:to_i) if time
      end
      [0, 0]
    end
  end
end
