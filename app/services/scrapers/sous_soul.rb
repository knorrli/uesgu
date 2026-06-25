require "set"

module Scrapers
  class SousSoul < Agent
    # The Webflow homepage is the event listing. List rows carry the start time
    # only on the detail page, which also exposes a year-qualified date in its
    # <title>, so click through for the fields.
    def self.url
      URI.parse("https://www.sous-soul.love/")
    end

    # Sous Soul lists a title + Untertitel only; there is no genre/style/tag field.
    field_gaps genres: :no_field

    # Each event renders twice in the list (a default + a hover variant); dedupe by
    # detail href so we don't fetch every detail page twice.
    def event_rows
      seen = Set.new
      page.css(".event_item.w-dyn-item").select do |row|
        href = row.at_css("a.link-block")&.attr("href")
        href.present? && seen.add?(href)
      end
    end

    def event_url(row)
      URI.join(self.class.url, link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    # The date block shows an English month + day with no year, but the page
    # <title> ("… | Jun 11, 2026 | SOUSSOUL") carries the year — parse that, and
    # take the start time from the detail's `.time` block.
    def event_start_time(content)
      title_text = content.at_css("title")&.text.to_s
      /(?<month>\p{L}{3,})\s+(?<day>\d{1,2}),\s+(?<year>\d{4})/ =~ title_text
      month = Date::ABBR_MONTHNAMES.index(month) || Date::MONTHNAMES.index(month)
      raise "Unparseable Sous Soul date: #{title_text.inspect}" if month.blank? || day.blank?

      time_string = content.at_css("div.time")&.text.to_s[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{year}-#{month}-#{day} #{time_string}")
    end

    def event_title(content)
      content.at_css("h2.event_title")&.text&.squish
    end

    def event_description(content)
      content.at_css("h2.event_title.untertitel")&.text&.squish
    end

    private

    def link_for(row)
      Page::Link.new(row.at_css("a.link-block"), @mech, page)
    end
  end
end
