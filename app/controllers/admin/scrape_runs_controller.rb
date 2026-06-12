module Admin
  # Scraper oversight: did last night's sweep work, and what did each venue do?
  class ScrapeRunsController < BaseController
    def index
      @presenter = ScrapeRunsPresenter.new
    end

    def show
      @run = ScrapeRun.find(params[:id])
      @results = @run.scrape_results.order(:scraper)
      @created_events = @run.created_events.order(:start_date, :title).includes(:locations).to_a
    end

    # Trigger a full sequential sweep on demand. The sweep takes minutes (it hits
    # every venue), so we create the run synchronously — which makes it visible
    # and blocks a second trigger — then run the rest in a background thread and
    # redirect straight away. No live tracking: refresh to see results land. (A
    # thread, not a job, because there's no background worker — see render.yaml.)
    def create
      if ScrapeRun.in_progress.exists?
        redirect_to admin_scrape_runs_path, alert: t('.already_running'), status: :see_other
        return
      end

      Scrapers::Sweep.enqueue(ScrapeRun.create!(started_at: Time.current))
      redirect_to admin_scrape_runs_path, notice: t('.started'), status: :see_other
    end
  end
end
