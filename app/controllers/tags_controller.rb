class TagsController < ApplicationController
  # index/chips power the public events filter autocomplete; filter_options serves
  # the filter sheets' option trees; edit is the inline (per-event) entry into the
  # genre tree/curation editor.
  allow_unauthenticated_access only: %i[ index chips filter_options ]
  before_action :require_admin, only: %i[ edit ]

  # Which partial renders a sheet's options. A closed map (the route constrains
  # :field to its keys) rather than interpolating the param into a template path.
  FILTER_OPTION_PARTIALS = { "what" => "tags/genre_options", "where" => "tags/location_options" }.freeze

  def index
    @tags = ActsAsTaggableOn::Tag
      .where.not(name: params[:applied])
      .ransack(name_cont: params[:q])
      .result
      .joins(:taggings)
      .where(taggings: { context: params[:context].presence, taggable_type: Event.name })
      .order(name: :asc)
      .select(:name, :context).distinct
  end

  def chips
    @tags = ActsAsTaggableOn::Tag
      .where(name: params[:combobox_values].to_s.split(","))
      .joins(:taggings)
      .where(taggings: { context: params[:context].presence, taggable_type: Event.name })
      .distinct
      .order(name: :asc)
  end

  # One filter sheet's option tree, fetched by its turbo-frame the first time the
  # sheet opens (filter-sheets#open) — see the route comment for why it isn't part
  # of the page. The tree itself is the same for every visitor (its counts are
  # global, not filter-scoped); only the ticks depend on the caller, so the applied
  # values ride in the query string and come back pre-checked. Rendering them here
  # rather than ticking client-side keeps the sheet's markup identical to what the
  # page used to ship inline.
  def filter_options
    @field = params[:field]
    @options_partial = FILTER_OPTION_PARTIALS.fetch(@field)
    @filter = Filter.build(genres: params[:g].presence, location_list: params[:l].presence)
  end

  # The gear icon on a genre tag opens the shared genre editor for that genre.
  def edit
    tag = ActsAsTaggableOn::Tag.find(params[:id])
    @genre = Genre.create_or_find_by!(name: tag.name)
    @alias_suggestions = AliasSuggester.call(@genre)
    @related_suggestions = RelatedGenreSuggester.call(@genre, exclude: @alias_suggestions.map(&:id))
    @sample_events = Event.tagged_with(@genre.name, on: :genres).order(start_date: :desc).limit(5)
  end
end
