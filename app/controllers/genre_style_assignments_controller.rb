class GenreStyleAssignmentsController < ApplicationController
  before_action :require_admin

  def index
    Rails.logger.info 'Loading index'
    @event_tag_stats = EventTagStatsPresenter.new
    @unassigned_genre_tags = @event_tag_stats.unassigned_genre_tags.order(name: :asc).page(params[:page]).per(1)
    Rails.logger.info 'After index'
  end

  def create
    styles = Style.where(id: genre_style_assignment_params[:style_ids].split(','))


    redirect_to genre_style_assignments_path(page: params[:page])
  end

  private

  def genre_style_assignment_params
    params.expect(genre_style_assignment: [:style_ids, :style_id, :tag_value])
  end
end
