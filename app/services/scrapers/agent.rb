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

    # Template method shared by every scraper. Subclasses provide only the venue
    # specifics via the hooks below (event_rows / event_url + field extractors);
    # the fetch-iterate-find-build-save-skip skeleton lives here once.
    def process_events
      get(self.class.url)

      event_rows.each do |row|
        @current_row = row
        next if skip_row?(row)

        url = event_url(row)
        next if url.blank?

        Rails.logger.info "Processing event URL #{url}"
        event = Event.find_or_initialize_by(url: url)
        transact do
          build_event(event, row)
          event.save!
        rescue StandardError => e
          record_failure(event, e)
        end
      end
    end

    # Assign every field from the event's content node. `event_content` is the row
    # itself for list-page scrapers; click-into-detail scrapers override it to fetch
    # and return the detail page. Wrapped in `transact` (a no-op when nothing is
    # navigated) so the agent's history is restored after each detail click.
    def build_event(event, row)
      content = event_content(row)
      preprocess(content)
      event.start_time    = event_start_time(content)
      event.start_date    = event.start_time.to_date
      event.title         = event_title(content)
      event.subtitle      = event_subtitle(content)
      event.genre_list    = event_genres(content)
      event.style_list    = event_styles(genres: event.genre_list)
      event.location_list = self.class.locations
      postprocess(event)
    end

    # The list row currently being processed. Exposed for the rare hybrid scraper
    # whose extractors need the row even after `event_content` clicks into a detail
    # page (see Kiff), and as the seam for future health/cancellation hooks.
    attr_reader :current_row

    # --- Hooks: required ---
    def event_rows
      raise NotImplementedError, "#{self.class} must implement #event_rows"
    end

    def event_url(_row)
      raise NotImplementedError, "#{self.class} must implement #event_url"
    end

    # --- Hooks: optional, with behaviour-preserving defaults ---

    # Skip a row before it becomes an event (e.g. non-concert entries).
    def skip_row?(_row) = false

    # The node field extractors read from. List-page default: the row itself.
    def event_content(row) = row

    # Run before field extraction (e.g. stateful year-rollover detection).
    def preprocess(_content) = nil

    # Many venues expose no subtitle / no genres; default to none.
    def event_subtitle(_content) = nil
    def event_genres(_content) = nil

    # Adjust the built event before saving (e.g. promote a blank title).
    def postprocess(_event) = nil

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
