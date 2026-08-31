namespace :scrapers do
  desc "Save live HTML fixtures for the scraper golden tests"
  task :capture_fixtures, [:only] => :environment do |_task, args|
    root = Rails.root.join("test/fixtures/scrapers")

    detail_link = {
      "bad_bonn"      => ".program-row .program-bands a",
      "kofmehl"       => ".events .events__element a.events__link",
      "docks"         => ".programme-container .mix.concerts a",
      "boeroem"       => ".ast-article-single .veranstaltung .elementor-heading-title a",
      "isc"           => "a.event_preview",
      "kiff"          => ".FilterPage__FilterResults > .Card-Event .Card__Link",
      "nouveau_monde" => ".poster[data-tofilter*=concert]",
      "sedel"         => ".programm ul > li a",
      "sous_soul"     => ".event_item.w-dyn-item a.link-block",
      "neubad"        => "ul.liste li.zeile .views-field-title a",
      "z7"            => ".block-event-calendar article a"
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
      File.binwrite(dir.join("list.html"), agent.page.body)
      print "ok"

      if (selector = detail_link[slug])
        node = agent.page.at_css(selector)
        href = node && node["href"]
        if href.present?
          detail_url = URI.join(klass.url.to_s, href).to_s
          print ", detail (#{detail_url})… "
          agent.get(detail_url)
          File.binwrite(dir.join("detail.html"), agent.page.body)
          print "ok"
        else
          print ", detail SELECTOR MISSED (#{selector})"
        end
      end
      puts

      sleep 1
    rescue StandardError => e
      puts "  FAILED #{slug}: #{e.class}: #{e.message}"
    end
  end

  desc "Run all scrapers once, recording a ScrapeRun and per-scraper summary (daily cron entrypoint)"
  task run_all: :environment do
    run = Scrapers::Sweep.run!
    ExtractionAttempt.prune!

    failed = run.scrape_results.failed.pluck(:scraper)
    dropped = run.dropped_to_zero
    snoozed = run.scrape_results.snoozed.pluck(:scraper)
    snoozed_note = snoozed.any? ? " · #{snoozed.size} snoozed (#{snoozed.join(', ')})" : ""

    if failed.any? || dropped.any?
      reasons = []
      reasons << "#{failed.size} FAILED (#{failed.join(', ')})" if failed.any?
      reasons << "#{dropped.size} DROPPED TO ZERO (#{dropped.join(', ')})" if dropped.any?
      puts format("scrapers:run_all: %s of %d scrapers in %.1fs%s — see /admin/scrape_runs",
                  reasons.join("; "), run.scrapers_total, run.duration, snoozed_note)
      abort("scrapers:run_all finished with failures")
    elsif run.scrapers_empty.positive?
      puts format("scrapers:run_all: all %d ran but %d produced no events in %.1fs%s — see /admin/scrape_runs",
                  run.scrapers_total, run.scrapers_empty, run.duration, snoozed_note)
    else
      puts format("scrapers:run_all: all %d scrapers OK in %.1fs%s", run.scrapers_total, run.duration, snoozed_note)
    end
  end

  namespace :rote_fabrik do
    desc "Backfill Rote Fabrik event URLs from the dead kalender. backend to the public SPA route"
    task fix_urls: :environment do
      dry = ENV["DRY_RUN"].present?
      old = Event.where(data_source: Scrapers::RoteFabrik.source_key)
                 .where("url LIKE ?", "%kalender.rotefabrik.ch%")
      if old.none?
        puts "rote_fabrik:fix_urls: nothing to do (no events on the old kalender. host)"
        next
      end

      agent = Scrapers::RoteFabrik.new
      agent.get(Scrapers::RoteFabrik.url)
      rows_by_rf = agent.send(:event_rows).index_by { |r| r["r_f_event_id"].to_s }

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

      verb = dry ? "would fix" : "fixed"
      puts "rote_fabrik:fix_urls: #{verb} #{fixed}, skipped #{skipped} (not in feed), #{collided} collision(s)#{' [DRY RUN]' if dry}"
    end
  end

  desc "Dry-run one scraper live and dump parsed events to tmp/dry_run/<slug>.json (no DB writes)"
  task :dry_run, [:scraper] => :environment do |_task, args|
    name = args[:scraper] or abort "usage: scrapers:dry_run[ClassName]"
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

      agent.transact do
        content = agent.send(:event_content, row)
        agent.send(:preprocess, content)
        start_time = agent.send(:event_start_time, content)
        genres = Array(agent.send(:event_genres, content))
        events << {
          url: url,
          start_time: start_time&.iso8601,
          start_date: start_time&.to_date&.iso8601,
          title: agent.send(:event_title, content),
          description: agent.send(:event_description, content),
          genres: genres
        }
      end
    rescue StandardError => e
      skipped << { url: url, error: "#{e.class}: #{e.message}" }
    end

    dir = Rails.root.join("tmp/dry_run")
    FileUtils.mkdir_p(dir)
    out = dir.join("#{name.underscore}.json")
    File.write(out, "#{JSON.pretty_generate(scraper: name, seen: rows.size, parsed: events.size, skipped: skipped, events: events)}\n")
    puts "#{name}: #{rows.size} rows, #{events.size} parsed, #{skipped.size} skipped → #{out}"
    puts "  skipped: #{skipped.first(3).map { |s| s[:error] }.join(' | ')}" if skipped.any?
  end
end
