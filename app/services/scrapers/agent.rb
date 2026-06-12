require 'rubygems'
require 'mechanize'

module Scrapers
  class Agent < Mechanize
    include Registerable

    def self.call
      new.call
    end

    # Returns a Scrapers::Result tallying what this run saw and wrote, so the
    # orchestrator (scrapers:run_all) can persist a ScrapeResult and stamp the
    # created events — without the Agent itself knowing about those tables.
    def call
      Rails.logger.info "Start processing #{self.class.location} at #{self.class.url}"

      process_events

      if @failures.positive?
        Rails.logger.warn "Finished #{self.class.location} with #{@failures} skipped event(s)"
      else
        Rails.logger.info "Finished processing #{self.class.location}"
      end

      Result.new(seen: @seen, created: @created, updated: @updated,
                 unchanged: @unchanged, skipped: @failures, created_ids: @created_ids)
    end

    private

    # Template method shared by every scraper. Subclasses provide only the venue
    # specifics via the hooks below (event_rows / event_url + field extractors);
    # the fetch-iterate-find-build-save-skip skeleton lives here once.
    def process_events
      # Counters live here (not in #call) so the offline golden harness, which
      # drives #process_events directly, initializes them too. #call reads them
      # back into the returned Result.
      @seen = @created = @updated = @unchanged = @failures = 0
      @created_ids = []

      get(self.class.url)

      event_rows.each do |row|
        @current_row = row
        next if skip_row?(row)

        @seen += 1

        # event_url runs inside the per-event rescue too: a single row missing its
        # anchor (markup tweak, teaser/ad card) must skip that event, not raise out
        # of the loop and abort the rest of the venue's programme.
        begin
          url = event_url(row)
        rescue StandardError => e
          record_failure(nil, e)
          next
        end
        next if url.blank?

        Rails.logger.info "Processing event URL #{url}"
        event = Event.find_or_initialize_by(url: url)
        # A dismissed event was intentionally removed by an admin; leave it
        # untouched so the re-scrape can't resurrect or update it back into view.
        next if event.dismissed?

        was_new = event.new_record?
        # Snapshot the persisted tags before build_event overwrites them, so we
        # can tell a real re-scrape change from a no-op (every re-scrape saves
        # the event, but most nights nothing actually changed).
        tags_before = was_new ? nil : tag_snapshot(event)
        transact do
          build_event(event, row)
          # Attribute changes (title/time/cancellation/…) come from Rails' dirty
          # tracking; tag changes (genres/styles) don't dirty the model, so diff
          # the snapshot separately.
          changed = event.changed? || (tags_before && tag_snapshot(event) != tags_before)
          event.save!
          if was_new
            @created += 1
            @created_ids << event.id
          elsif changed
            @updated += 1
          else
            @unchanged += 1
          end
        rescue StandardError => e
          record_failure(event, e)
        end
      end
    end

    # The event's tag lists, for comparing pre/post build_event. genres drive
    # styles, but both are cheap and explicit; locations are a per-venue constant
    # so they never change and aren't worth the extra load.
    def tag_snapshot(event)
      { genres: event.genre_list.sort, styles: event.style_list.sort }
    end

    # Assign every field from the event's content node. `event_content` is the row
    # itself for list-page scrapers; click-into-detail scrapers override it to fetch
    # and return the detail page. Wrapped in `transact` (a no-op when nothing is
    # navigated) so the agent's history is restored after each detail click.
    def build_event(event, row)
      content = event_content(row)
      preprocess(content)
      # Skip any field an admin has manually edited and locked, so the re-scrape
      # can't overwrite the correction (Event#overridden? — the field-level
      # sibling of the dismissed-event skip above). start_date trails start_time
      # unless independently locked, so a locked time keeps both consistent.
      event.start_time    = event_start_time(content) unless event.overridden?(:start_time)
      event.start_date    = event.start_time.to_date  unless event.overridden?(:start_date)
      event.title         = event_title(content)      unless event.overridden?(:title)
      event.subtitle      = event_subtitle(content)   unless event.overridden?(:subtitle)
      # Trusted (discovery) genres from a clean structured field may mint new
      # taxonomy; consumption genres from an unstable free-text source are
      # attached match-only, never creating a Genre row (see Genre.existing_only).
      event.genre_list    = Array(event_genres(content)) +
                            Genre.existing_only(event_consumption_genres(content))
      event.style_list    = event_styles(genres: event.genre_list)
      # Derive visibility from source each scrape, mirroring Event#recompute_styles!
      # — otherwise a freshly-scraped non-music event (hidden genre, no style) would
      # stay publicly visible until a later disposition/recompute touched it.
      event.hidden        = event.hidden_by_genre?
      event.location_list = self.class.locations
      postprocess(event)
      mark_cancellation(event, content)
    end

    # Cancellation markers in German / French / Italian / English. Letter-bounded
    # (Unicode-aware, so accents work) to avoid matching inside unrelated words
    # like "Cancellara". Deliberately excludes "verschoben"/"reporté"/"postponed"
    # — a postponed show keeps a (new) date and is not a cancellation.
    CANCELLATION_MARKER = /
      (?<![[:alpha:]])
      (?: abgesagt | annul(?:é|ée|és|ées|ation) | annullat[oa] | cancell?ed )
      (?![[:alpha:]])
    /xi

    # Derive (and keep re-deriving) the cancellation flag from the source, like
    # styles — set it while the marker is present, clear it once it's gone, and
    # preserve the original timestamp across re-scrapes.
    def mark_cancellation(event, content)
      event.cancelled_at =
        if event_cancelled?(event, content)
          event.cancelled_at || Time.current
        end
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

    # Trusted genres: a clean, structured genre/style field the venue curates.
    # These may mint new taxonomy (discovery). Default: none.
    def event_genres(_content) = nil

    # Consumption genres: from an UNSTABLE free-text source (artist blurbs,
    # subtitle prose, parsed titles, origin codes). Attached match-only against
    # the curated vocabulary so they never create taxonomy from noise. A scraper
    # that mixes a clean field and a messy one overrides both. Default: none.
    def event_consumption_genres(_content) = nil

    # Adjust the built event before saving (e.g. promote a blank title).
    def postprocess(_event) = nil

    # Whether the event reads as cancelled. Default: a cancellation marker in the
    # venue-extracted title/subtitle (the common "ABGESAGT: …" / "Annulé" prefix)
    # — NOT a full-HTML scan, which false-matches boilerplate, JS and other
    # events. A venue that exposes a dedicated status element should override this
    # to read it precisely from `content`.
    def event_cancelled?(event, _content)
      CANCELLATION_MARKER.match?([event.title, event.subtitle].compact.join("\n"))
    end

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
      Genre.styles_for(genres)
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
