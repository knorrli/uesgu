module Scrapers
  class Sweep
    def self.run!(scrapers: All.scrapers, out: $stdout)
      perform(ScrapeRun.create!(started_at: Time.current), scrapers: scrapers, out: out)
    end

    def self.perform(run, scrapers: All.scrapers, out: $stdout)
      new(scrapers, out).perform(run)
    end

    def self.enqueue(run, scrapers: All.scrapers)
      Thread.new do
        Rails.application.executor.wrap { perform(run, scrapers: scrapers) }
      rescue StandardError => e
        Rails.logger.error("Background scrape run ##{run.id} crashed: #{e.class}: #{e.message}")
      end
    end

    def initialize(scrapers, out)
      @scrapers = scrapers
      @out = out
    end

    def perform(run)
      ScraperSnooze.prune_expired!
      snoozed = ScraperSnooze.active_by_slug
      @scrapers.each do |name, klass|
        slug = name.underscore
        if (snooze = snoozed[slug])
          skip(run, slug, snooze)
        else
          record(run, slug, klass)
        end
      end

      Dedup.run

      Genre.reconcile!
      Locality.reconcile!
      CapturedVenueLeads.refresh!
      finalize(run)
      ScrapeRun.prune!
      run
    end

    private

    def skip(run, slug, snooze)
      @out.puts "[#{slug}] SNOOZED until #{snooze.snoozed_until.iso8601} — skipping"
      run.scrape_results.create!(scraper: slug, status: :snoozed,
                                 started_at: Time.current, duration_ms: 0)
    end

    def record(run, slug, klass)
      started = Time.current
      @out.puts "[#{slug}] starting #{klass.url}"

      result = klass.call
      processed = result.created + result.updated + result.unchanged
      status = processed.positive? ? :ok : :empty
      run.scrape_results.create!(
        scraper: slug, status: status, started_at: started, duration_ms: ms_since(started),
        rows_seen: result.seen, created_count: result.created, updated_count: result.updated,
        unchanged_count: result.unchanged, errored_count: result.errored,
        discarded_count: result.discarded, robots_note: result.robots_note
      )
      @out.puts "[#{slug}] ROBOTS #{result.robots_note}" if result.robots_note.present?
      if result.created_ids.any?
        Event.where(id: result.created_ids).update_all(created_in_scrape_run_id: run.id)
      end
      @out.puts format("[%s] %s in %.1fs (%d seen, +%d new, ~%d updated, %d errored, %d filtered)",
                       slug, status.to_s.upcase, ms_since(started) / 1000.0,
                       result.seen, result.created, result.updated, result.errored, result.discarded)
    rescue StandardError => e
      run.scrape_results.create!(
        scraper: slug, status: :failed, started_at: started, duration_ms: ms_since(started),
        error_class: e.class.name, error_message: e.message&.truncate(1000)
      )
      Rails.logger.error("[#{slug}] scrape failed: #{e.class}: #{e.message}")
      @out.puts format("[%s] FAILED in %.1fs — %s: %s", slug, ms_since(started) / 1000.0, e.class, e.message)
    end

    def finalize(run)
      results = run.scrape_results
      run.update!(
        status: :finished, finished_at: Time.current,
        scrapers_total: results.count,
        scrapers_ok: results.ok.count,
        scrapers_empty: results.empty.count,
        scrapers_failed: results.failed.count
      )
    end

    def ms_since(started)
      ((Time.current - started) * 1000).round
    end
  end
end
