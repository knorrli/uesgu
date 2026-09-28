module Scrapers
  module EventPageSchedule
    def self.due?(event, today: Date.current)
      checked_on = event.event_page_checked_at&.to_date
      return true if checked_on.nil?

      checked_on <= today - interval_days(event.start_date - today)
    end

    def self.interval_days(days_away)
      if days_away <= 3 then 1
      elsif days_away <= 7 then 2
      else 7
      end
    end
  end
end
