namespace :casing do
  desc "Report what Casing.recase would change across event titles and descriptions " \
       "and place and locality names, grouped by source. Reads only — nothing is " \
       "written. Run it against a fresh scrape before wiring the recaser in, and read " \
       "the listing rather than the totals: a wrong recase is a wrong NAME, which the " \
       "counts cannot show you."
  task report: :environment do
    CasingReport.call($stdout)
  end
end
