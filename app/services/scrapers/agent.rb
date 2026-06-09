require 'rubygems'
require 'mechanize'

module Scrapers
  class Agent < Mechanize
    include Registerable

    def self.call
      new.call
    end

    def call
      Rails.logger.info "Start processing #{self.class.location} at #{self.class.url}"

      @failures = 0
      process_events

      if @failures.positive?
        Rails.logger.warn "Finished #{self.class.location} with #{@failures} skipped event(s)"
      else
        Rails.logger.info "Finished processing #{self.class.location}"
      end
    end

    private

    # Log and skip a single event that failed to parse or save, so one bad
    # event doesn't abort the rest of a venue's programme. A total failure
    # (e.g. the site being down) raises before/around the loop instead, so the
    # job still surfaces as failed in Mission Control.
    def record_failure(event, error)
      @failures = @failures.to_i + 1
      Rails.logger.error(
        "[#{self.class.location}] Skipped event #{event&.url}: #{error.class}: #{error.message}"
      )
    end

    # Derive styles from the genre → style mapping. Also registers any new
    # genres (unmapped, so they surface in the assignment queue) — the styles
    # of a still-unmapped genre are simply none.
    def event_styles(genres:)
      Genre.ensure!(genres)
      Style.joins(:genres).where(genres: { name: genres }).distinct.pluck(:name)
    end

    def month_number(month:)
      month_numbers[month].presence || month
    end

    def month_numbers
      @month_numbers ||= {
        'Jan' => 1, 'Januar' => 1,
        'Feb' => 2, 'Februar' => 2,
        'Mär' => 3, 'Mrz' => 3, 'März' => 3,
        'Apr' => 4, 'April' => 4,
        'Mai' => 5,
        'Jun' => 6, 'Juni' => 6,
        'Jul' => 7, 'Juli' => 7,
        'Aug' => 8, 'August' => 8,
        'Sep' => 9, 'Sept' => 9, 'September' => 9,
        'Okt' => 10, 'Oktober' => 10,
        'Nov' => 11, 'November' => 11,
        'Dez' => 12, 'Dezember' => 12
      }
    end
  end
end
