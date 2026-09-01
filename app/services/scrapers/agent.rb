require "rubygems"
require "mechanize"

module Scrapers
  class Agent < Mechanize
    include Registerable

    USER_AGENT = "uesgu/1.0 (+https://uesgu.ch; personal event aggregator)".freeze

    class_attribute :respect_robots, instance_writer: false, default: true

    class_attribute :_field_gaps, instance_accessor: false, default: {}.freeze

    def initialize
      super
      self.user_agent = USER_AGENT
      self.robots = respect_robots
    end

    # webrobots (0.1.2) FAIL-CLOSES: when the robots.txt REQUEST fails — a 5xx, a
    # TLS handshake failure, a reset, a timeout — it fabricates a synthetic
    # "Disallow: /" and Mechanize raises RobotsDisallowedError, a verdict the venue
    # never issued. So an unreachable robots.txt is UNKNOWN, not a ban: proceed,
    # and record it. RFC 9309 §2.3.1.4 permits this for a site we can tell is
    # misconfigured — schuur.ch serves its programme at 200 and 500s only on
    # /robots.txt. A genuine Disallow (or a `noindex` meta tag) stashes no fetch
    # error, which is what tells the two apart. 4xx never reaches here: Mechanize's
    # get_robots maps it to an empty robots.txt (§2.3.1.3, allow-all).
    def get(*args, &block)
      return without_robots { super } if robots_unreachable?(robots_origin(args.first))

      super
    rescue Mechanize::RobotsDisallowedError => e
      cause = robots_fetch_error(e.uri)
      raise unless cause

      note_robots_unreachable(e.uri, cause)
      without_robots { super }
    end

    def robots_note
      return nil if robots_unreachable.empty?

      robots_unreachable.map { |origin, cause| "#{origin}/robots.txt unreachable — #{cause}" }.join("; ")
    end

    def self.call
      new.call
    end

    def self.source_key
      name.demodulize
    end

    def self.aggregator?
      false
    end

    def self.venue
      Venue.find_by_domain(venue_domains.first)
    end

    def self.location
      venue&.name
    end

    def self.locations
      venue&.place_tuple || [location].compact
    end

    def self.venue_domains
      return [] if aggregator?

      [Discovery.domain(url.host)].compact
    end

    def self.event_url_pattern
      return nil if aggregator?
      %r{\Ahttps?://#{Regexp.escape(url.host)}/}
    end

    FIELD_GAP_REASONS = %i[no_field dormant].freeze

    def self.field_gaps(**gaps)
      return _field_gaps if gaps.empty?

      gaps.each do |field, reason|
        next if FIELD_GAP_REASONS.include?(reason)

        raise ArgumentError,
              "unknown field-gap reason #{reason.inspect} for #{field.inspect} " \
              "(one of: #{FIELD_GAP_REASONS.join(', ')})"
      end
      self._field_gaps = _field_gaps.merge(gaps).freeze
    end

    def call
      Rails.logger.info "Start processing #{self.class.location} at #{self.class.url}"

      process_events

      if @failures.positive?
        Rails.logger.warn "Finished #{self.class.location} with #{@failures} errored event(s)"
      else
        Rails.logger.info "Finished processing #{self.class.location}"
      end

      Result.new(seen: @seen, created: @created, updated: @updated,
                 unchanged: @unchanged, errored: @failures, discarded: @discarded,
                 created_ids: @created_ids, robots_note: robots_note)
    end

    private

    def robots_unreachable
      @robots_unreachable ||= {}
    end

    def robots_unreachable?(origin)
      origin.present? && robots_unreachable.key?(origin)
    end

    def note_robots_unreachable(uri, cause)
      origin = robots_origin(uri)
      return if origin.blank? || robots_unreachable.key?(origin)

      robots_unreachable[origin] = "#{cause.class}: #{cause.message}"
      Rails.logger.warn(
        "[#{self.class.location}] #{origin}/robots.txt is unreachable " \
        "(#{cause.class}: #{cause.message}) — no ban was published, so proceeding"
      )
    end

    def robots_origin(target)
      uri = URI(target.to_s)
      "#{uri.scheme}://#{uri.host}" if uri.scheme && uri.host
    rescue StandardError
      nil
    end

    def robots_fetch_error(uri)
      agent.robots_error(uri)
    end

    def without_robots
      self.robots = false
      yield
    ensure
      self.robots = respect_robots
    end

    def process_events
      @seen = @created = @updated = @unchanged = @failures = @discarded = 0
      @created_ids = []

      get(self.class.url)

      event_rows.each do |row|
        @current_row = row
        next if skip_row?(row)

        @seen += 1

        begin
          url = event_url(row)
        rescue StandardError => e
          record_failure(nil, e)
          next
        end
        next if url.blank?

        Rails.logger.info "Processing event URL #{url}"
        event = Event.find_or_initialize_by(url: url)
        next if event.dismissed?

        was_new = event.new_record?
        tags_before = was_new ? nil : tag_snapshot(event)
        transact do
          build_event(event, row)
          event.save!
          fields = was_new ? nil : changed_fields(event, tags_before)
          if was_new
            @created += 1
            @created_ids << event.id
          elsif fields.any?
            @updated += 1
            Rails.logger.info "Updated #{event.url} — changed: #{fields.join(', ')}"
          else
            @unchanged += 1
          end
        rescue StandardError => e
          record_failure(event, e)
        end
      end
    end

    def tag_snapshot(event)
      { genres: event.genre_list.sort, locations: event.location_list.sort }
    end

    def changed_fields(event, tags_before)
      fields = event.saved_changes.keys - %w[created_at updated_at genre_list location_list]
      after = tag_snapshot(event)
      fields << "genres"    if after[:genres]    != tags_before[:genres]
      fields << "locations" if after[:locations] != tags_before[:locations]
      fields
    end

    def build_event(event, row)
      content = event_content(row)
      preprocess(content)
      event.start_time    = event_start_time(content) unless event.overridden?(:start_time)
      event.start_date    = event.start_time.to_date  unless event.overridden?(:start_date)
      event.title         = event_title(content)      unless event.overridden?(:title)
      event.description   = event_description(content)   unless event.overridden?(:description)
      unless event.overridden?(:genres)
        event.genre_list = Array(event_genres(content)) + mined_genres(content)
      end
      ensure_genres_and_visibility(event)
      event.location_list = event_locations(content) unless event.overridden?(:locations)
      event.data_source   = self.class.source_key
      postprocess(event)
      mark_cancellation(event, content)
      mark_reschedule(event, content)
      mark_discarded(event)
    end

    def mark_discarded(event)
      rule = discard_rules.detect do |r|
        r.matches?(title: event.title, description: event.description, location: self.class.location)
      end
      event.discarded_by_rule_id = rule&.id
      @discarded += 1 if rule
    end

    def discard_rules
      @discard_rules ||= DiscardRule.active.by_recency.to_a
    end

    CANCELLATION_MARKER = /
      (?<![[:alpha:]])
      (?: abgesagt | annul(?:é|ée|és|ées|ation) | annullat[oa] | cancell?ed )
      (?![[:alpha:]])
    /xi

    def mark_cancellation(event, content)
      event.cancelled_at =
        if event_cancelled?(event, content)
          event.cancelled_at || Time.current
        end
    end

    RESCHEDULE_MARKER = /
      (?<![[:alpha:]])
      (?:
          verschoben | verlegt
        | neue[rs]?\s+(?:termin|datum)
        | report(?:ées|és|ée|é)
        | nouvelle\s+date
        | rinviat[oa] | posticipat[oa]
        | postponed | rescheduled
        | new\s+date
      )
      (?![[:alpha:]])
    /xi

    def mark_reschedule(event, content)
      event.rescheduled_at =
        if event_rescheduled?(event, content)
          event.rescheduled_at || Time.current
        end
    end

    attr_reader :current_row

    def event_rows
      raise NotImplementedError, "#{self.class} must implement #event_rows"
    end

    def event_url(_row)
      raise NotImplementedError, "#{self.class} must implement #event_url"
    end

    def skip_row?(_row) = false

    def event_content(row) = row

    def event_locations(_content) = self.class.locations

    def preprocess(_content) = nil

    def event_description(_content) = nil

    def event_genres(_content) = nil

    def event_genre_prose(_content) = nil

    def postprocess(_event) = nil

    def event_cancelled?(event, _content)
      CANCELLATION_MARKER.match?([event.title, event.description].compact.join("\n"))
    end

    def event_rescheduled?(event, _content)
      RESCHEDULE_MARKER.match?([event.title, event.description].compact.join("\n"))
    end

    def record_failure(event, error)
      @failures = @failures.to_i + 1
      Rails.logger.error(
        "[#{self.class.location}] Skipped event #{event&.url}: #{error.class}: #{error.message}"
      )
    end

    def parse_json(body, default: [])
      JSON.parse(body)
    rescue JSON::ParserError => e
      Rails.logger.error("[#{self.class.location}] feed returned unparseable JSON: #{e.message}")
      default
    end

    def mined_genres(content)
      text = event_genre_prose(content)
      return [] if text.blank?

      Genre.names_in_prose(text, genre_mining_index)
    end

    def genre_mining_index
      @genre_mining_index ||= Genre.prose_mining_index
    end

    def ensure_genres_and_visibility(event)
      Genre.ensure!(event.genre_list)
      event.hidden = event.hidden_by_genre?
    end

    def month_number(month:)
      month_numbers[month].presence || month
    end

    def month_numbers
      @month_numbers ||= {
        "Jan" => 1, "Januar" => 1,
        "Feb" => 2, "Februar" => 2,
        "Mär" => 3, "Mrz" => 3, "März" => 3,
        "Apr" => 4, "April" => 4,
        "Mai" => 5,
        "Jun" => 6, "Juni" => 6,
        "Jul" => 7, "Juli" => 7,
        "Aug" => 8, "August" => 8,
        "Sep" => 9, "Sept" => 9, "September" => 9,
        "Okt" => 10, "Oktober" => 10,
        "Nov" => 11, "November" => 11,
        "Dez" => 12, "Dezember" => 12
      }
    end
  end
end
