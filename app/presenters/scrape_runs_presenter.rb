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

  def tally(run)
    results = run.scrape_results
    { total: results.size, ok: results.count(&:ok?),
      empty: results.count(&:empty?), failed: results.count(&:failed?) }
  end

  def scrapers
    Scrapers::All.scrapers.keys.map(&:underscore).sort
  end

  def latest_result(scraper)
    result_for(latest, scraper)
  end

  def active_snoozes
    @active_snoozes ||= ScraperSnooze.active_by_slug
  end

  def snoozed_count(run)
    run.scrape_results.count(&:snoozed?)
  end

  def history(scraper)
    runs.reverse.map { |run| result_for(run, scraper) }
  end

  private

  def result_for(run, scraper)
    run&.scrape_results&.find { |r| r.scraper == scraper }
  end
end
