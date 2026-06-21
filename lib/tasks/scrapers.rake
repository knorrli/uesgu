namespace :scrapers do
  # Capture one list page per venue (+ one detail page per click-into-detail venue)
  # into test/fixtures/scrapers/<venue>/ for the golden parser tests. Read-only HTTP,
  # no DB writes. Re-run when a venue's markup changes and a golden goes stale.
  #
  #   bin/rails scrapers:capture_fixtures            # all venues
  #   bin/rails scrapers:capture_fixtures[kofmehl]   # one venue
  desc 'Save live HTML fixtures for the scraper golden tests'
  task :capture_fixtures, [:only] => :environment do |_task, args|
    root = Rails.root.join('test/fixtures/scrapers')

    # First-detail-link selector for each click-into-detail (Shape B) scraper, so we
    # can grab a representative detail page the same way the scraper would.
    detail_link = {
      'bad_bonn'      => '.program-row .program-bands a',
      'kofmehl'       => '.events .events__element a.events__link',
      'docks'         => '.programme-container .mix.concerts a',
      'boeroem'       => '.ast-article-single .veranstaltung .elementor-heading-title a',
      'isc'           => 'a.event_preview',
      'kiff'          => '.FilterPage__FilterResults > .Card-Event .Card__Link',
      'nouveau_monde' => '.poster[data-tofilter*=concert]',
      'sedel'         => '.programm ul > li a',
      'sous_soul'     => '.event_item.w-dyn-item a.link-block',
      'neubad'        => 'ul.liste li.zeile .views-field-title a'
    }

    only = args[:only]
    Scrapers::All.scrapers.each do |demodulized, klass|
      slug = demodulized.underscore
      next if only.present? && only != slug

      dir = root.join(slug)
      FileUtils.mkdir_p(dir)
      agent = klass.new

      print "#{slug}: list… "
      agent.get(klass.url)
      File.binwrite(dir.join('list.html'), agent.page.body)
      print 'ok'

      if (selector = detail_link[slug])
        node = agent.page.at_css(selector)
        href = node && node['href']
        if href.present?
          detail_url = URI.join(klass.url.to_s, href).to_s
          print ", detail (#{detail_url})… "
          agent.get(detail_url)
          File.binwrite(dir.join('detail.html'), agent.page.body)
          print 'ok'
        else
          print ", detail SELECTOR MISSED (#{selector})"
        end
      end
      puts

      sleep 1 # be a courteous guest
    rescue StandardError => e
      puts "  FAILED #{slug}: #{e.class}: #{e.message}"
    end
  end

  # Run every scraper once, sequentially. This is the entrypoint for the daily
  # Render cron (see render.yaml) that replaced the in-Puma Solid Queue worker.
  #
  # Records the sweep into a ScrapeRun + per-scraper ScrapeResult rows (the
  # /admin/scrape_runs oversight page reads these), stamps the events each
  # scraper created with the run, prints a per-scraper summary to stdout (which
  # Render captures as the cron job's live log), and exits non-zero if a scraper
  # raised OR a venue that produced events last run came back empty (a silent
  # drop-to-zero — HTTP 200 but the markup broke). Render's failure notification
  # then fires for a site being down or a quietly-broken parser, but NOT for a
  # venue that's simply chronically empty (that surfaces in-app instead). A
  # per-event parse error is skipped and counted inside the scraper.
  #
  #   bin/rails scrapers:run_all
  desc 'Run all scrapers once, recording a ScrapeRun and per-scraper summary (daily cron entrypoint)'
  task run_all: :environment do
    run = Scrapers::Sweep.run!

    failed = run.scrape_results.failed.pluck(:scraper)
    dropped = run.dropped_to_zero

    if failed.any? || dropped.any?
      reasons = []
      reasons << "#{failed.size} FAILED (#{failed.join(', ')})" if failed.any?
      reasons << "#{dropped.size} DROPPED TO ZERO (#{dropped.join(', ')})" if dropped.any?
      puts format('scrapers:run_all: %s of %d scrapers in %.1fs — see /admin/scrape_runs',
                  reasons.join('; '), run.scrapers_total, run.duration)
      abort('scrapers:run_all finished with failures')
    elsif run.scrapers_empty.positive?
      puts format('scrapers:run_all: all %d ran but %d produced no events in %.1fs — see /admin/scrape_runs',
                  run.scrapers_total, run.scrapers_empty, run.duration)
    else
      puts format('scrapers:run_all: all %d scrapers OK in %.1fs', run.scrapers_total, run.duration)
    end
  end

  # One-off backfill: rewrite the stored Rote Fabrik event URLs that the old
  # event_url built wrongly — they pointed at the login-gated `kalender.` backend
  # using `r_f_event_id`, which 404s to a visitor (a dead link in the app). The
  # fixed scraper now emits the public SPA route keyed on the occurrence id. Since
  # events are matched on `url`, the next scrape would otherwise CREATE fresh rows
  # and orphan the old ones — so run this BEFORE the next sweep to heal in place.
  #
  # Fetches the live feed and reuses the scraper's own event_url so the rewritten
  # URL is byte-identical to what re-scraping produces. Idempotent: only touches
  # rows still on the old `kalender.` host; an event whose id has dropped from the
  # feed (can't be remapped) is reported and left untouched. Run on prod via the
  # Render shell after deploy.
  #
  #   bin/rails scrapers:rote_fabrik:fix_urls          # apply
  #   DRY_RUN=1 bin/rails scrapers:rote_fabrik:fix_urls # preview only
  namespace :rote_fabrik do
    desc 'Backfill Rote Fabrik event URLs from the dead kalender. backend to the public SPA route'
    task fix_urls: :environment do
      dry = ENV['DRY_RUN'].present?
      old = Event.where(data_source: Scrapers::RoteFabrik.source_key)
                 .where('url LIKE ?', '%kalender.rotefabrik.ch%')
      if old.none?
        puts 'rote_fabrik:fix_urls: nothing to do (no events on the old kalender. host)'
        next
      end

      agent = Scrapers::RoteFabrik.new
      agent.get(Scrapers::RoteFabrik.url)
      # r_f_event_id (the id baked into the OLD url) → the live row, so we can rebuild
      # the new url via the scraper's own event_url.
      rows_by_rf = agent.send(:event_rows).index_by { |r| r['r_f_event_id'].to_s }

      fixed = skipped = collided = 0
      old.find_each do |event|
        rf_id = event.url[%r{events/(\d+)}, 1]
        row = rows_by_rf[rf_id]
        unless row
          skipped += 1
          puts "  SKIP ##{event.id} #{event.title} — r_f_event_id #{rf_id} no longer in feed (#{event.url})"
          next
        end

        new_url = agent.send(:event_url, row)
        clash = Event.where(url: new_url).where.not(id: event.id).exists?
        if clash
          collided += 1
          puts "  SKIP ##{event.id} #{event.title} — target URL already exists (#{new_url}); needs manual merge"
          next
        end

        puts "  ##{event.id} #{event.title}: #{event.url} → #{new_url}"
        event.update!(url: new_url) unless dry
        fixed += 1
      end

      verb = dry ? 'would fix' : 'fixed'
      puts "rote_fabrik:fix_urls: #{verb} #{fixed}, skipped #{skipped} (not in feed), #{collided} collision(s)#{' [DRY RUN]' if dry}"
    end
  end

  # REVIEW-ONLY dry run for vetting a draft scraper before it's wired in. Runs the
  # scraper LIVE (real get/page/click) but mirrors build_event into a plain hash
  # instead of an Event — so it never touches the DB, never mints genres, and never
  # derives styles (raw genres are reported instead, which is what a human needs to
  # eyeball date/title correctness). Writes tmp/dry_run/<slug>.json and prints a
  # summary. NOT part of the nightly sweep.
  #
  #   bin/rails "scrapers:dry_run[Treibhaus]"   # by demodulized class name
  desc 'Dry-run one scraper live and dump parsed events to tmp/dry_run/<slug>.json (no DB writes)'
  task :dry_run, [:scraper] => :environment do |_task, args|
    name = args[:scraper] or abort 'usage: scrapers:dry_run[ClassName]'
    klass = Scrapers::All.scrapers[name] or abort "unknown scraper #{name.inspect} (have: #{Scrapers::All.scrapers.keys.sort.join(', ')})"

    agent = klass.new
    agent.get(klass.url)
    rows = agent.send(:event_rows)

    events = []
    skipped = []
    rows.each do |row|
      agent.instance_variable_set(:@current_row, row)
      next if agent.send(:skip_row?, row)

      url = agent.send(:event_url, row)
      next if url.blank?

      # transact restores the agent's page after a click-into-detail scraper
      # navigates away, exactly as build_event does — a no-op for list-page scrapers.
      agent.transact do
        content = agent.send(:event_content, row)
        agent.send(:preprocess, content)
        start_time = agent.send(:event_start_time, content)
        genres = Array(agent.send(:event_genres, content)) +
                 Array(agent.send(:event_consumption_genres, content))
        events << {
          url: url,
          start_time: start_time&.iso8601,
          start_date: start_time&.to_date&.iso8601,
          title: agent.send(:event_title, content),
          subtitle: agent.send(:event_subtitle, content),
          genres: genres
        }
      end
    rescue StandardError => e
      skipped << { url: url, error: "#{e.class}: #{e.message}" }
    end

    dir = Rails.root.join('tmp/dry_run')
    FileUtils.mkdir_p(dir)
    out = dir.join("#{name.underscore}.json")
    File.write(out, "#{JSON.pretty_generate(scraper: name, seen: rows.size, parsed: events.size, skipped: skipped, events: events)}\n")
    puts "#{name}: #{rows.size} rows, #{events.size} parsed, #{skipped.size} skipped → #{out}"
    puts "  skipped: #{skipped.first(3).map { |s| s[:error] }.join(' | ')}" if skipped.any?
  end
end
