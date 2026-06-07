class TagsController < ApplicationController
  # index/chips power the public events filter autocomplete; the rest is tag management.
  allow_unauthenticated_access only: %i[ index chips ]
  before_action :require_admin, only: %i[ edit update destroy ]

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
      .where(name: params[:combobox_values].split(','))
      .joins(:taggings)
      .where(taggings: { context: params[:context].presence, taggable_type: Event.name })
      .distinct
      .order(name: :asc)
  end

  def edit
    @tag = ActsAsTaggableOn::Tag.find(params[:id])
  end

  def update
    @tag = ActsAsTaggableOn::Tag.find(params[:id])
    @tag.update(tag_params)

    redirect_back fallback_location: admin_path
  end

  def destroy
    @tag = ActsAsTaggableOn::Tag.find(params[:id])
    @tag.discard

    redirect_back fallback_location: admin_path
  end

  def tag_params
    params.expect(acts_as_taggable_on_tag: [:name, :style_ids])
  end
end
