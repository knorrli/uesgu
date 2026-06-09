class AdminController < ApplicationController
  before_action :require_admin

  def index
    @event_tag_stats = EventTagStatsPresenter.new
  end
end
