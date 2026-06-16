module Admin
  # Read-only browser over the scraped events table. Mirrors the genres index:
  # filter by visibility status, sort, free-text title search, paginate. Unlike
  # the public index (scoped to :visible), the admin sees everything.
  class EventsController < BaseController
    # "hidden" = non-music events suppressed from the public listing; "cancelled"
    # = called-off shows that stay listed publicly with a marker; "dismissed" =
    # admin-soft-deleted (gone from public, never re-scraped back). The first
    # three exclude dismissed so it only surfaces under its own filter.
    STATUS_SCOPES = {
      'visible' => -> { Event.visible },
      'hidden' => -> { Event.kept.where(hidden: true) },
      'cancelled' => -> { Event.kept.cancelled },
      'dismissed' => -> { Event.dismissed }
    }.freeze

    # Chronological by default — oldest/nearest-term events first (the bulk of the
    # table is upcoming, so this surfaces what's current rather than the furthest-
    # out shows); 'title' is the alphabetical lookup.
    SORT_SCOPES = {
      'date' => ->(scope) { scope.order(start_date: :asc, start_time: :asc) },
      'title' => ->(scope) { scope.order(:title) }
    }.freeze

    def index
      @status = STATUS_SCOPES.key?(params[:status]) ? params[:status] : 'all'
      @sort = SORT_SCOPES.key?(params[:sort]) ? params[:sort] : 'date'
      # "all" means all kept events — dismissed ones are reached via their filter.
      scope = @status == 'all' ? Event.kept : STATUS_SCOPES[@status].call
      scope = scope.where('title ILIKE ?', "%#{params[:q]}%") if params[:q].present?
      @events = SORT_SCOPES[@sort].call(scope).includes(:locations, :styles).page(params[:page]).per(50)
    end

    def show
      @event = Event.find(params.expect(:id))
    end

    # Manual correction of an event's fields. Locking is implicit on edit: any
    # overridable field whose value the admin actually changed is added to
    # overridden_fields, so the next re-scrape leaves it alone. Date + time are
    # locked as a pair (either change locks both) so start_time's date can never
    # diverge from start_date. A genre edit also re-derives the styles/visibility
    # that hang off the genres.
    def update
      @event = Event.find(params.expect(:id))
      attrs = params.expect(event: %i[title subtitle date time override_genre_ids])
      assign_scalars(@event, attrs)
      locked = @event.changed & Event::OVERRIDABLE_FIELDS
      locked |= SCHEDULE_FIELDS if locked.intersect?(SCHEDULE_FIELDS)
      locked << 'genres' if assign_genres(@event, attrs)
      @event.overridden_fields = (@event.overridden_fields + locked).uniq
      @event.save!
      @event.recompute_styles! if locked.include?('genres')
      redirect_to admin_event_path(@event), notice: t('.saved')
    end

    # Release one locked field (or the date/time pair) back to the scraper; the
    # next run refills it from source.
    def revert
      event = Event.find(params.expect(:id))
      fields = SCHEDULE_FIELDS.include?(params[:field]) ? SCHEDULE_FIELDS : [params[:field]]
      fields.each { |field| event.release_field!(field) }
      redirect_to admin_event_path(event), notice: t('.reverted')
    end

    # Soft-delete: the event drops out of every public listing and is never
    # resurrected by a re-scrape (Scrapers::Agent skips dismissed events).
    # Reversible via #undismiss — not a hard delete.
    def destroy
      event = Event.find(params.expect(:id))
      event.dismiss!
      redirect_to admin_events_path(status: 'dismissed'), notice: t('.dismissed')
    end

    # Lift a dismissal so the event reappears and re-scrapes resume updating it.
    def undismiss
      event = Event.find(params.expect(:id))
      event.undismiss!
      redirect_to admin_event_path(event), notice: t('.restored')
    end

    private

    # start_date + start_time move together: the form edits a date and a
    # time-of-day, and a change to either locks both.
    SCHEDULE_FIELDS = %w[start_date start_time].freeze

    def assign_scalars(event, attrs)
      event.title = attrs[:title]
      event.subtitle = attrs[:subtitle].presence
      date = attrs[:date].present? ? Date.parse(attrs[:date]) : event.start_date
      event.start_date = date
      event.start_time =
        if attrs[:time].present?
          hour, minute = attrs[:time].split(':').map(&:to_i)
          Time.zone.local(date.year, date.month, date.day, hour, minute)
        end
    end

    # Pin the genre list to the admin's combobox selection (comma-joined Genre
    # ids; mapped back to names, which Event's genre_list= setter canonicalizes
    # and de-blocks). A missing field is left alone; an empty selection clears the
    # list. Returns whether it actually changed, so the caller knows to lock it.
    def assign_genres(event, attrs)
      return false unless attrs.key?(:override_genre_ids)

      ids = attrs[:override_genre_ids].to_s.split(',').map(&:strip).reject(&:blank?)
      before = event.genre_list.sort
      event.genre_list = Genre.where(id: ids).pluck(:name)
      event.genre_list.sort != before
    end
  end
end
