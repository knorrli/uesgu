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
      'sedel'         => '.programm ul > li a'
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
      print "ok"

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
end
