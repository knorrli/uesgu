class TagsController < ApplicationController
  # index/chips power the public events filter autocomplete; edit is the inline
  # (per-event) entry into the genre tree/curation editor.
  allow_unauthenticated_access only: %i[ index chips ]
  before_action :require_admin, only: %i[ edit ]

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

  # The gear icon on a genre tag opens the shared genre editor for that genre.
  def edit
    tag = ActsAsTaggableOn::Tag.find(params[:id])
    @genre = Genre.create_or_find_by!(name: tag.name)
    @alias_suggestions = AliasSuggester.call(@genre)
    @related_suggestions = RelatedGenreSuggester.call(@genre, exclude: @alias_suggestions.map(&:id))
    @sample_events = Event.tagged_with(@genre.name, on: :genres).order(start_date: :desc).limit(5)
  end
end
