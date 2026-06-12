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

    # Manual correction of an event's scalar fields. Locking is implicit on edit:
    # any overridable field whose value the admin actually changed is added to
    # overridden_fields, so the next re-scrape leaves it alone. Date + time are
    # locked as a pair (either change locks both) so start_time's date can never
    # diverge from start_date.
    def update
      @event = Event.find(params.expect(:id))
      assign_edits(@event)
      locked = @event.changed & Event::OVERRIDABLE_FIELDS
      locked |= SCHEDULE_FIELDS if locked.intersect?(SCHEDULE_FIELDS)
      @event.overridden_fields = (@event.overridden_fields + locked).uniq
      @event.save!
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

    private

    # start_date + start_time move together: the form edits a date and a
    # time-of-day, and a change to either locks both.
    SCHEDULE_FIELDS = %w[start_date start_time].freeze

    def assign_edits(event)
      attrs = params.expect(event: %i[title subtitle date time])
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
  end
end
