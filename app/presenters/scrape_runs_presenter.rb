# Backs the /admin/scrape_runs index: the latest sweep at a glance plus a short
# per-scraper history strip so a flapping or newly-broken venue stands out. Loads
# the most recent runs once (with their results) and pivots them in memory.
class ScrapeRunsPresenter
  HISTORY = 14

  def initialize
    @runs = ScrapeRun.recent.includes(:scrape_results).limit(HISTORY).to_a
  end

  attr_reader :runs

  def latest
    runs.first
  end

  def in_progress?
    ScrapeRun.in_progress.exists?
  end

  # Every known scraper slug, so a venue that produced no result at all (e.g. it
  # was added but never ran, or crashed before recording) still gets a row.
  def scrapers
    Scrapers::All.scrapers.keys.map(&:underscore).sort
  end

  def latest_result(scraper)
    result_for(latest, scraper)
  end

  # Oldest → newest, so the strip reads left-to-right like a timeline. nil slots
  # are runs where this scraper produced no result.
  def history(scraper)
    runs.reverse.map { |run| result_for(run, scraper) }
  end

  private

  def result_for(run, scraper)
    run&.scrape_results&.find { |r| r.scraper == scraper }
  end
end
