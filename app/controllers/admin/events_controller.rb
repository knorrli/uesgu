module Admin
  class EventsController < BaseController
    include CatalogueBrowsing

    STATUS_SCOPES = {
      "visible" => -> { Event.visible },
      "hidden" => -> { Event.kept.where(hidden: true) },
      "cancelled" => -> { Event.kept.cancelled },
      "discarded" => -> { Event.discarded },
      "duplicates" => -> { Event.duplicates },
      "dismissed" => -> { Event.dismissed }
    }.freeze

    SORT_SCOPES = {
      "date" => ->(scope) { scope.order(start_date: :asc, start_time: :asc) },
      "title" => ->(scope) { scope.order(:title) }
    }.freeze

    def index
      @status = catalogue_param(:status, STATUS_SCOPES, default: "all")
      @sort = catalogue_param(:sort, SORT_SCOPES, default: "date")
      scope = @status == "all" ? Event.kept.canonical : STATUS_SCOPES[@status].call
      scope = scope.where("title ILIKE ?", "%#{params[:q]}%") if params[:q].present?
      @events = SORT_SCOPES[@sort].call(scope)
                                  .includes(:locations, :genres, :discarded_by_rule, :canonical_event)
                                  .page(params[:page]).per(PAGE_SIZE)
      @duplicate_counts = Event.where(canonical_event_id: @events.map(&:id)).group(:canonical_event_id).count
    end

    def show
      @event = Event.find(params.expect(:id))
    end

    def search
      scope = Event.kept.canonical.where.not(id: params[:exclude])
      scope = scope.where("title ILIKE ?", "%#{params[:q]}%") if params[:q].present?
      @events = scope.includes(:locations).order(start_date: :asc).limit(20)
    end

    def update
      @event = Event.find(params.expect(:id))
      attrs = params.expect(event: %i[title description date time genres place locality canton])
      assign_scalars(@event, attrs)
      locked = @event.changed & Event::OVERRIDABLE_FIELDS
      locked |= SCHEDULE_FIELDS if locked.intersect?(SCHEDULE_FIELDS)
      locked << "genres" if assign_genres(@event, attrs)

      tags = location_tags(attrs)
      return redirect_to admin_event_path(@event), alert: t(".place_invalid") if tags&.place_invalid?

      locked << "locations" if tags && assign_locations(@event, tags)
      @event.overridden_fields = (@event.overridden_fields + locked).uniq
      @event.save!
      @event.recompute_visibility! if locked.include?("genres")
      redirect_to admin_event_path(@event), notice: t(".saved")
    end

    def revert
      event = Event.find(params.expect(:id))
      fields = SCHEDULE_FIELDS.include?(params[:field]) ? SCHEDULE_FIELDS : [params[:field]]
      fields.each { |field| event.release_field!(field) }
      redirect_to admin_event_path(event), notice: t(".reverted")
    end

    def destroy
      event = Event.find(params.expect(:id))
      event.dismiss!
      redirect_to admin_events_path(status: "dismissed"), notice: t(".dismissed")
    end

    def undismiss
      event = Event.find(params.expect(:id))
      event.undismiss!
      redirect_to admin_event_path(event), notice: t(".restored")
    end

    def merge
      event = Event.find(params.expect(:id))
      canonical = Event.find_by(id: params[:canonical_id])
      return redirect_to admin_event_path(event), alert: t(".merge_missing") if canonical.nil?

      event.merge_into!(canonical)
      redirect_to admin_event_path(canonical), notice: t(".merged")
    rescue ArgumentError => e
      redirect_to admin_event_path(event), alert: e.message
    end

    def unmerge
      event = Event.find(params.expect(:id))
      event.mark_standalone!
      redirect_to admin_event_path(event), notice: t(".unmerged")
    end

    private

    SCHEDULE_FIELDS = %w[start_date start_time].freeze

    def assign_scalars(event, attrs)
      event.title = attrs[:title]
      event.description = attrs[:description].presence
      date = attrs[:date].present? ? Date.parse(attrs[:date]) : event.start_date
      event.start_date = date
      event.start_time =
        if attrs[:time].present?
          hour, minute = attrs[:time].split(":").map(&:to_i)
          Time.zone.local(date.year, date.month, date.day, hour, minute)
        end
    end

    def location_tags(attrs)
      return if attrs[:locality].blank?

      LocationTags.call(place: attrs[:place], locality: attrs[:locality], canton: attrs[:canton])
    end

    def assign_locations(event, tags)
      before = event.location_list.sort
      event.location_list = tags.names
      event.location_list.sort != before
    end

    def assign_genres(event, attrs)
      return false unless attrs.key?(:genres)

      before = event.genre_list.sort
      event.genre_list = attrs[:genres].to_s.split(",").map(&:strip).compact_blank
      event.genre_list.sort != before
    end
  end
end
