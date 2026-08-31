module Admin
  class ScrapeRunsController < BaseController
    def index
      @presenter = ScrapeRunsPresenter.new
    end

    def show
      @run = ScrapeRun.find(params[:id])
      @results = @run.scrape_results.order(:scraper).to_a
      @created_events = @run.created_events.order(:start_date, :title).includes(:locations).to_a
      @in_progress = ScrapeRun.in_progress.exists?
      @active_snoozes = ScraperSnooze.active_by_slug
    end

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

    def snooze
      slug = known_scraper_slug or return refuse_unknown_scraper
      ScraperSnooze.snooze!(slug)
      redirect_to admin_scrape_runs_path, notice: t(".snoozed", scraper: slug), status: :see_other
    end

    def wake
      slug = known_scraper_slug or return refuse_unknown_scraper
      ScraperSnooze.wake!(slug)
      redirect_to admin_scrape_runs_path, notice: t(".woke", scraper: slug), status: :see_other
    end

    private

    def known_scraper_slug
      slug = params[:scraper].presence
      slug if slug && Scrapers::All.scrapers.keys.any? { |name| name.underscore == slug }
    end

    def refuse_unknown_scraper
      redirect_to admin_scrape_runs_path,
                  alert: t("admin.scrape_runs.create.unknown_scraper"), status: :see_other
    end

    def selected_scrapers
      slug = params[:scraper].presence
      return Scrapers::All.scrapers unless slug

      match = Scrapers::All.scrapers.find { |name, _| name.underscore == slug }
      match ? { match[0] => match[1] } : {}
    end

    def trigger_notice(scrapers)
      if params[:scraper].present?
        t("admin.scrape_runs.create.started_one", scraper: scrapers.keys.first.underscore)
      else
        t("admin.scrape_runs.create.started")
      end
    end
  end
end
