module Scrapers
  # Runs every scraper once, sequentially, recording the sweep as a ScrapeRun +
  # per-scraper ScrapeResult rows and stamping the events each scraper created
  # with the run. Extracted from the scrapers:run_all rake task so the
  # orchestration is testable without Rake; the task keeps only the stdout
  # summary + exit-code policy that Render's cron alerting depends on.
  class Sweep
    # Create the run and execute it. The cron entrypoint uses this.
    def self.run!(scrapers: All.scrapers, out: $stdout)
      perform(ScrapeRun.create!(started_at: Time.current), scrapers: scrapers, out: out)
    end

    # Execute an already-created run. The manual /admin trigger creates the run
    # synchronously (so the UI and the in-progress guard see it immediately),
    # then calls this in a background thread.
    def self.perform(run, scrapers: All.scrapers, out: $stdout)
      new(scrapers, out).perform(run)
    end

    # Run a sweep off the request thread. There's no background worker (Solid
    # Queue was dropped — see render.yaml), so this is a plain thread with the
    # Rails executor managing the connection checkout. The seam the controller
    # calls, so tests can stub it instead of spawning real work.
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

    # Returns the finished ScrapeRun so the caller can decide exit status.
    def perform(run)
      @scrapers.each { |name, klass| record(run, name.underscore, klass) }

      # Collapse cross-source duplicates (PETZI vs our bespoke scrapers) once every
      # scraper has run, before reconcile so the canonical's merged genres count.
      Dedup.run

      # Refresh genre usage counts once after the full sweep so newly seen genres
      # surface in the assignment queue (the old per-scraper job did this each time).
      Genre.reconcile!
      finalize(run)
      ScrapeRun.prune!
      run
    end

    private

    def record(run, slug, klass)
      started = Time.current
      @out.puts "[#{slug}] starting #{klass.url}"

      result = klass.call
      # ok = processed at least one event (created/updated/unchanged); empty =
      # ran clean but processed none, the silent regression this exists to catch.
      # Unchanged counts as processed: a re-scrape that changed nothing is still
      # a healthy run, not an empty one.
      processed = result.created + result.updated + result.unchanged
      status = processed.positive? ? :ok : :empty
      run.scrape_results.create!(
        scraper: slug, status: status, started_at: started, duration_ms: ms_since(started),
        rows_seen: result.seen, created_count: result.created, updated_count: result.updated,
        unchanged_count: result.unchanged, errored_count: result.errored,
        discarded_count: result.discarded
      )
      if result.created_ids.any?
        Event.where(id: result.created_ids).update_all(created_in_scrape_run_id: run.id)
      end
      @out.puts format('[%s] %s in %.1fs (%d seen, +%d new, ~%d updated, %d errored, %d filtered)',
                       slug, status.to_s.upcase, ms_since(started) / 1000.0,
                       result.seen, result.created, result.updated, result.errored, result.discarded)
    rescue StandardError => e
      # A total failure (site down, robots block, markup that breaks before the
      # loop) raises out of #call; record it and carry on to the next venue. The
      # @out.puts is the cron's plain summary stream; log at ERROR too so the
      # failure carries a severity in Render's log stream, like every other
      # handled scraper error.
      run.scrape_results.create!(
        scraper: slug, status: :failed, started_at: started, duration_ms: ms_since(started),
        error_class: e.class.name, error_message: e.message&.truncate(1000)
      )
      Rails.logger.error("[#{slug}] scrape failed: #{e.class}: #{e.message}")
      @out.puts format('[%s] FAILED in %.1fs — %s: %s', slug, ms_since(started) / 1000.0, e.class, e.message)
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
