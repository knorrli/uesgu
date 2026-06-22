require 'rubygems'
require 'mechanize'

module Scrapers
  class Agent < Mechanize
    include Registerable

    # Identify the crawler honestly and obey robots.txt. Mechanize defaults
    # robots to false; we opt in so every scraper respects a venue's wishes.
    # We match the generic `User-agent: *` group — we are a personal events
    # reader, not ClaudeBot/GPTBot, so AI-crawler blocks don't apply to us.
    # A disallowed listing page raises Mechanize::RobotsDisallowedError out of
    # `get`, surfacing the venue as a failed run rather than silently scraping.
    USER_AGENT = 'uesgu/1.0 (+https://uesgu.ch; personal event aggregator)'.freeze

    # Per-venue escape hatch. Mechanize's single `robots` flag gates BOTH the
    # robots.txt check and the page-level `noindex, nofollow` meta tag. Some
    # venues ship one of these as an unconsidered CMS/site-builder default, not
    # a deliberate crawl ban — for those we opt out here, with a comment in the
    # scraper explaining why. The default stays strict: a scraper respects
    # robots unless it sets `self.respect_robots = false`.
    class_attribute :respect_robots, instance_writer: false, default: true

    # Backing store for the `field_gaps` macro below. A frozen default so the
    # unset case shares one empty hash; each declaring scraper gets its own.
    class_attribute :_field_gaps, instance_accessor: false, default: {}.freeze

    def initialize
      super
      self.user_agent = USER_AGENT
      self.robots = respect_robots
    end

    def self.call
      new.call
    end

    # The provenance stamp written to every event this scraper owns (Event#data_source).
    # Defaults to the demodulized class name ("Kofmehl", "Petzi").
    def self.source_key
      name.demodulize
    end

    # Most scrapers represent exactly one venue and declare a real
    # `[venue, city, canton]` place (see Location). A multi-venue aggregator
    # (e.g. Petzi) resolves the venue per event instead, so its class-level
    # `location`/`locations` are placeholders that must NOT seed the location
    # taxonomy — Location skips aggregators when building its hierarchy.
    def self.aggregator?
      false
    end

    # The canonical venue domain(s) this scraper consumes (eTLD+1), reconciled
    # against config/venue_ledger.yml by the ledger drift test. Single-venue
    # default: the registrable domain of its `url`. Overridden by: a multi-venue
    # aggregator that can enumerate its venues (Petzi), and a single-venue scraper
    # whose feed is hosted on a SaaS/operator backend so `url.host` isn't the venue
    # (Bar59 → firestore.googleapis.com, Dynamo → dynamo.nodehive.app). An
    # aggregator that resolves venues only per-event returns [] (it commits to no
    # fixed domain), exempting it from the reverse drift check.
    def self.venue_domains
      return [] if aggregator?

      [Discovery.domain(url.host)].compact
    end

    # The shape every event URL this scraper emits MUST match, asserted by the
    # golden suite against every captured URL. A wrong host or path-base here ships
    # dead links into the app (the Rote Fabrik failure: the public pages live on
    # rotefabrik.ch, but the feed host is the login-gated kalender.rotefabrik.ch).
    # Default: scheme + the listing host, which covers single-venue scrapers whose
    # event pages live on the same host as their feed. Override when the event host
    # differs from the feed host (a SaaS/operator backend, an admin calendar), and
    # pin the full path shape when the URL is built from an id so an id/path
    # regression can't slip through. Aggregators resolve a per-event host, so they
    # commit to no single shape and opt out with nil.
    def self.event_url_pattern
      return nil if aggregator?
      %r{\Ahttps?://#{Regexp.escape(url.host)}/}
    end

    # The controlled vocabulary of *why* a coverage field is absent at a source,
    # mirroring venue_ledger.yml's `reasons:` map — a small fixed set so the
    # coverage page can explain every gap consistently and a settled "does this
    # source even expose X?" call isn't re-litigated. The symbol is the stable
    # key; the human text lives in i18n (admin.scraper_coverage.index.gap_reason.*).
    #
    #   no_field — the source carries no such field at all (structural).
    #   dormant  — the field exists in the feed but the source never populates it
    #              (e.g. an always-empty `tags` array). Distinct from no_field
    #              because it may "wake up": the page's reality-wins rule then
    #              surfaces the live % the moment real values arrive.
    FIELD_GAP_REASONS = %i[no_field dormant].freeze

    # Declare (and read) the coverage fields this source structurally cannot
    # fill. A *capability* fact, kept on the scraper because the scraper is the
    # code that actually knows what the upstream exposes — it can't rot the way a
    # separate capability doc would. The coverage page (ScraperCoveragePresenter)
    # reads this to report a genuinely-absent field as "n/a (reason)" instead of
    # flagging an impossible-to-fill cell red, so the same gap isn't
    # re-investigated on every glance. Honesty is preserved by the page itself:
    # if a field declared absent ever ships real coverage, the live percentage
    # wins over the declaration, so a stale gap self-corrects rather than masking
    # newly collected data.
    #
    # Macro form declares (`field_gaps genres: :no_field, description: :no_field`);
    # the bare form reads. Merges down the class hierarchy so an OLE subclass can
    # add its own. Keys are coverage fields (:description, :genres); values come from
    # FIELD_GAP_REASONS. Declare ONLY a field that is absent at the SOURCE — never
    # one that's merely unbuilt (that's a defect to fix, not a gap to record).
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

    # Returns a Scrapers::Result tallying what this run saw and wrote, so the
    # orchestrator (scrapers:run_all) can persist a ScrapeResult and stamp the
    # created events — without the Agent itself knowing about those tables.
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
                 created_ids: @created_ids)
    end

    private

    # Template method shared by every scraper. Subclasses provide only the venue
    # specifics via the hooks below (event_rows / event_url + field extractors);
    # the fetch-iterate-find-build-save-skip skeleton lives here once.
    def process_events
      # Counters live here (not in #call) so the offline golden harness, which
      # drives #process_events directly, initializes them too. #call reads them
      # back into the returned Result.
      @seen = @created = @updated = @unchanged = @failures = @discarded = 0
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
          event.save!
          # Decide updated-vs-unchanged from what actually PERSISTED, not from
          # event.changed?: AATO re-flags the virtual genre_list/location_list
          # attributes dirty whenever the raw scraped spelling differs from the
          # stored canonical one (e.g. "indie rock" → stored "Indie Rock"), a no-op
          # that canonicalizes straight back and persists nothing. changed_fields
          # ignores that flag and compares real columns + the tag-set snapshot.
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

    # The event's tags, for comparing pre/post build_event. Locations are usually a
    # per-venue constant, but they can still drift (a casing/spelling change in the
    # venue array), so snapshot them too — same false-positive class as genres.
    def tag_snapshot(event)
      { genres: event.genre_list.sort, locations: event.location_list.sort }
    end

    # The field(s) that genuinely changed on a re-scrape — empty means "nothing
    # really changed", even when event.changed? was true. Real DB columns come from
    # saved_changes (what actually persisted), minus timestamps and the virtual
    # genre_list/location_list attributes AATO marks dirty on every assignment; tag
    # changes come from diffing the pre-build snapshot. A scraper whose extractor
    # yields an unstable value (whitespace, timezone, a volatile "N tickets left"
    # description) then shows the SAME field on every run in the "Updated … — changed:"
    # log — a one-line grep instead of guessing offline.
    def changed_fields(event, tags_before)
      fields = event.saved_changes.keys - %w[created_at updated_at genre_list location_list]
      after = tag_snapshot(event)
      fields << 'genres'    if after[:genres]    != tags_before[:genres]
      fields << 'locations' if after[:locations] != tags_before[:locations]
      fields
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
      event.description   = event_description(content)   unless event.overridden?(:description)
      # Every genre a scraper extracts — whether from a clean structured field or
      # mined from unstable free text (artist blurbs, descriptions, origin codes) —
      # mints taxonomy: an unrecognised token arrives UNPLACED in the admin
      # curation queue (to be filed into the tree, aliased, or blocked) rather than
      # being dropped at ingest. We collect everything and clean downstream — the
      # query-time alias link means raw tokens are safe to keep (see Genre).
      # Skip when an admin has pinned the list (Event#overridden?(:genres)) so the
      # re-scrape can't overwrite the correction — the field-level genre sibling
      # of the scalar skips above.
      # The genre set is the scraper's own extraction PLUS any known genre names
      # mined from a dropped description blob (mined_genres — off unless a scraper
      # opts into event_genre_prose). Mining is match-only over the existing
      # taxonomy, so it can't mint, only attach; event_genres is what mints. Both
      # are skipped together when an admin has pinned the list.
      unless event.overridden?(:genres)
        event.genre_list = Array(event_genres(content)) + mined_genres(content)
      end
      # Visibility (the music gate) is a derived projection of whatever genres now
      # stand — scraped or admin-pinned — so a pinned genre list still derives the
      # right hidden flag. Re-derived from source each scrape, mirroring
      # Event#recompute_visibility! — otherwise a freshly-scraped non-music event
      # (only hidden genres) would stay publicly visible until a later recompute.
      ensure_genres_and_visibility(event)
      event.location_list = event_locations(content)
      event.data_source   = self.class.source_key
      postprocess(event)
      mark_cancellation(event, content)
      mark_reschedule(event, content)
      mark_discarded(event)
    end

    # Re-derive the admin discard-rule flag from the current active rules, like
    # mark_cancellation derives the cancellation flag — so a junk event (e.g. a
    # football viewing with no genre) drops out of public listings on every
    # scrape, and clears again the moment its rule is removed. The matching here
    # mirrors DiscardRule#matching_events (its single source of truth).
    def mark_discarded(event)
      rule = discard_rules.detect do |r|
        r.matches?(title: event.title, description: event.description, location: self.class.location)
      end
      event.discarded_by_rule_id = rule&.id
      @discarded += 1 if rule
    end

    # Active discard rules, loaded once per run.
    def discard_rules
      @discard_rules ||= DiscardRule.active.by_recency.to_a
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

    # Reschedule markers — a show that MOVED but keeps a (new) date, the exact
    # counterpart to CANCELLATION_MARKER (which deliberately excludes these). The
    # same German / French / Italian / English coverage, letter-bounded
    # (Unicode-aware) so accents work and we don't match inside unrelated words;
    # the "new date" phrases allow flexible whitespace. Keyword-only by design —
    # a silent date move (no wording) is intentionally NOT flagged here, to avoid
    # false positives from minor time tweaks / parse noise (see the redesign notes).
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

    # Derive the reschedule flag from the source, exactly like mark_cancellation:
    # set it while a reschedule marker is present in the title/description, clear it
    # once gone, and preserve the original timestamp across re-scrapes.
    def mark_reschedule(event, content)
      event.rescheduled_at =
        if event_rescheduled?(event, content)
          event.rescheduled_at || Time.current
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

    # The [venue, city, canton] tags for this event. Single-venue scrapers use the
    # class constant; a multi-venue scraper (PETZI) overrides this to resolve the
    # venue per event. Default preserves every existing scraper's behaviour.
    def event_locations(_content) = self.class.locations

    # Run before field extraction (e.g. stateful year-rollover detection).
    def preprocess(_content) = nil

    # Many venues expose no description / no genres; default to none.
    def event_description(_content) = nil

    # Every genre a scraper extracts for an event, from whatever source — a clean
    # structured genre/style field the venue curates, or tokens mined from unstable
    # free text (artist blurbs, description prose, parsed titles, origin codes). All
    # of it mints taxonomy: an unrecognised token lands UNPLACED in the curation
    # queue to be filed, aliased, or blocked, rather than dropped at ingest.
    # Default: none.
    def event_genres(_content) = nil

    # Opt-in seam for ingest-time genre mining. Several venues expose NO genre
    # field, yet the description prose they fetch (and otherwise drop) names real,
    # matchable styles. A scraper for such a venue overrides this to return that
    # blob as plain text; the base then attaches any genre names it contains that
    # ALREADY EXIST in the taxonomy (see mined_genres). Default: none (no mining),
    # so this is inert for every scraper that doesn't opt in.
    def event_genre_prose(_content) = nil

    # Adjust the built event before saving (e.g. promote a blank title).
    def postprocess(_event) = nil

    # Whether the event reads as cancelled. Default: a cancellation marker in the
    # venue-extracted title/description (the common "ABGESAGT: …" / "Annulé" prefix)
    # — NOT a full-HTML scan, which false-matches boilerplate, JS and other
    # events. A venue that exposes a dedicated status element should override this
    # to read it precisely from `content`.
    def event_cancelled?(event, _content)
      CANCELLATION_MARKER.match?([event.title, event.description].compact.join("\n"))
    end

    # Whether the event reads as rescheduled — a reschedule marker in the
    # venue-extracted title/description ("Verschoben", "neues Datum", "new date", …).
    # Same shape as event_cancelled?; a venue with a dedicated status element can
    # override this to read it precisely from `content`.
    def event_rescheduled?(event, _content)
      RESCHEDULE_MARKER.match?([event.title, event.description].compact.join("\n"))
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

    # Parse a JSON feed body, logging at ERROR and falling back to `default` when
    # the source returns something unparseable (an error page, a truncated
    # response, a changed content type). A bare `rescue JSON::ParserError` here
    # would turn a broken feed into a silent zero-row run; routing every JSON-feed
    # scraper through this one helper means a broken feed always surfaces as an
    # ERROR line tagged with the venue — handled, but not swallowed.
    def parse_json(body, default: [])
      JSON.parse(body)
    rescue JSON::ParserError => e
      Rails.logger.error("[#{self.class.location}] feed returned unparseable JSON: #{e.message}")
      default
    end

    # The known genre names found in this event's dropped description prose —
    # match-only against the existing taxonomy (mints nothing). Empty unless the
    # scraper opts in via event_genre_prose. The mineable vocabulary is loaded
    # once per run (genres don't change mid-scrape) and reused across every event.
    def mined_genres(content)
      text = event_genre_prose(content)
      return [] if text.blank?

      Genre.names_in_prose(text, genre_mining_index)
    end

    def genre_mining_index
      @genre_mining_index ||= Genre.prose_mining_index
    end

    # Ensure a Genre row exists for each tagged genre (so brand-new ones surface in
    # the curation queue) and set the music-gate visibility from their dispositions.
    def ensure_genres_and_visibility(event)
      Genre.ensure!(event.genre_list)
      event.hidden = event.hidden_by_genre?
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
