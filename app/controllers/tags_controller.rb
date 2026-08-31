class TagsController < ApplicationController
  allow_unauthenticated_access only: %i[ index chips filter_options ]
  before_action :require_admin, only: %i[ edit ]

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

  def filter_options
    @field = params[:field]
    @options_partial = FILTER_OPTION_PARTIALS.fetch(@field)
    @filter = Filter.build(genres: params[:g].presence, location_list: params[:l].presence)
  end

  def edit
    tag = ActsAsTaggableOn::Tag.find(params[:id])
    @genre = Genre.create_or_find_by!(name: tag.name)
    @alias_suggestions = AliasSuggester.call(@genre)
    @related_suggestions = RelatedGenreSuggester.call(@genre, exclude: @alias_suggestions.map(&:id))
    @sample_events = Event.tagged_with(@genre.name, on: :genres).order(start_date: :desc).limit(5)
  end
end
