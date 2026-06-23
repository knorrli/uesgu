module Admin
  # Scraper oversight: did last night's sweep work, and what did each venue do?
  # Also the on-demand triggers (full sweep, or a single scraper).
  class ScrapeRunsController < BaseController
    def index
      @presenter = ScrapeRunsPresenter.new
    end

    def show
      @run = ScrapeRun.find(params[:id])
      @results = @run.scrape_results.order(:scraper).to_a
      @created_events = @run.created_events.order(:start_date, :title).includes(:locations).to_a
      @in_progress = ScrapeRun.in_progress.exists?
    end

    # Trigger a run on demand: the full sweep, or a single scraper when a
    # `scraper` slug is given (re-run one venue after fixing its parser, without
    # waiting on all the others). The sweep takes a while (it hits live sites),
    # so we create the run synchronously — which makes it visible and blocks a
    # second concurrent trigger — then run the rest in a background thread and
    # redirect straight away. No live tracking beyond the page's own poll-refresh.
    # (A thread, not a job, because there's no background worker — see render.yaml.)
    def create
      if ScrapeRun.in_progress.exists?
        return redirect_to admin_scrape_runs_path, alert: t(".already_running"), status: :see_other
      end

      scrapers = selected_scrapers
      if scrapers.empty?
        return redirect_to admin_scrape_runs_path, alert: t(".unknown_scraper"), status: :see_other
      end

      Scrapers::Sweep.enqueue(ScrapeRun.create!(started_at: Time.current), scrapers: scrapers)
      redirect_to admin_scrape_runs_path, notice: trigger_notice(scrapers), status: :see_other
    end

    private

    # All scrapers, or just the one whose slug was posted (empty hash = the slug
    # matched nothing, so the caller refuses the trigger).
    def selected_scrapers
      slug = params[:scraper].presence
      return Scrapers::All.scrapers unless slug

      match = Scrapers::All.scrapers.find { |name, _| name.underscore == slug }
      match ? { match[0] => match[1] } : {}
    end

    # Relative keys (`t('.started')`) would scope to this helper's name under
    # i18n static analysis; at runtime they resolve against the `create` action.
    # Spell them out so the scanner and runtime agree.
    def trigger_notice(scrapers)
      if params[:scraper].present?
        t("admin.scrape_runs.create.started_one", scraper: scrapers.keys.first.underscore)
      else
        t("admin.scrape_runs.create.started")
      end
    end
  end
end
