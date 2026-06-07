require 'rubygems'
require 'mechanize'

module Scrapers
  class Agent < Mechanize
    include Registerable

    class ScrapeError < StandardError
      attr_reader :event

      def initialize(message, event)
        @event = event
        super("#{message}, Event: #{event.attributes}")
      end
    end

    def self.call
      new.call
    end

    def call
      Rails.logger.info "Start processing #{self.class.location} at #{self.class.url}"

      process_events

      Rails.logger.info "Finished processing #{self.class.location}"
    end

    private

    def event_styles(genres:)
      Style.tagged_with(genres, any: true).pluck(:name)
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
