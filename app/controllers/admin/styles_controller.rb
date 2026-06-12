module Admin
  # Read-only browser over the curated style vocabulary (the closed set genres
  # map onto). Mirrors the genres index: filter by mapping status, sort, search,
  # paginate. The vocabulary is tiny, so usage counts come from one grouped query
  # and the filter/sort happen in Ruby over the loaded set.
  class StylesController < BaseController
    STATUSES = %w[all assigned unassigned].freeze
    SORTS = %w[name count].freeze

    def index
      @status = STATUSES.include?(params[:status]) ? params[:status] : 'all'
      @sort = SORTS.include?(params[:sort]) ? params[:sort] : 'name'
      @usage = Style.event_usage_counts

      styles = Style.includes(:genres).to_a
      # "assigned" = at least one genre maps to it; "unassigned" = an orphan style
      # no genre points at (dead vocabulary worth pruning).
      styles.select! { |style| style.genres.any? } if @status == 'assigned'
      styles.select! { |style| style.genres.empty? } if @status == 'unassigned'
      if params[:q].present?
        needle = params[:q].downcase
        styles.select! { |style| style.name.to_s.downcase.include?(needle) }
      end

      styles = if @sort == 'count'
                 styles.sort_by { |style| [-@usage[style.name].to_i, style.name.to_s.downcase] }
      else
                 styles.sort_by { |style| style.name.to_s.downcase }
      end

      @styles = Kaminari.paginate_array(styles).page(params[:page]).per(50)
    end
  end
end
