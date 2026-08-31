module Scrapers
  class MuehleHunziken < Agent
    DATE_SLUG = /-(?<y>\d{4})-(?<mo>\d{2})-(?<d>\d{2})\z/

    def self.url
      URI.parse("https://muehlehunziken.ch/programm")
    end

    def event_rows
      page.css("li.wavy-bottom")
    end

    def skip_row?(row)
      row_href(row).to_s !~ DATE_SLUG
    end

    def event_url(row)
      row_href(row)
    end

    def event_content(row)
      click(link_for(row))
    end

    def event_start_time(content)
      date = row_href(current_row).match(DATE_SLUG)
      raise "Unparseable Mühle date: #{row_href(current_row).inspect}" if date.nil?

      hour, minute = show_time(content)
      Time.zone.local(date[:y].to_i, date[:mo].to_i, date[:d].to_i, hour, minute)
    end

    def event_title(content)
      current_row.at_css("h2")&.text&.squish
    end

    def event_description(_content)
      div = current_row.css("div").find do |node|
        classes = node["class"].to_s
        classes.include?("text-sm") && classes.include?("md:text-xl")
      end
      div&.text&.squish.presence
    end

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
