class AdminController < ApplicationController
  before_action :require_admin

  def index
    @event_tag_stats = EventTagStatsPresenter.new
    @latest_scrape_run = ScrapeRun.recent.first
  end
end
