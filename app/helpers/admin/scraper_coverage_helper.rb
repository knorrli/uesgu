module Admin
  module ScraperCoverageHelper
    # Below this fill-rate, a cell is flagged for a look: either the scraper could
    # be collecting more, or its extractor broke. (Not green — green is reserved
    # for "interested"; this is an attention state, so it uses the warn colour.)
    COVERAGE_LOW = 50

    # One fill-rate cell for a coverage field (:time/:subtitle/:genres). Em dash
    # when the scraper has no events to measure; "n/a" (muted, with the reason on
    # hover) when the source structurally can't provide the field — a declared
    # gap, not a failure, so never red; otherwise the percentage, flagged --low
    # when too many events lack the field.
    def coverage_cell(row, field)
      return tag.span('—', class: 'muted') unless row.present?

      if (reason = row.gap_for(field))
        return tag.span(
          t('admin.scraper_coverage.index.gap'),
          class: 'coverage coverage--gap',
          title: t("admin.scraper_coverage.index.gap_reason.#{reason}")
        )
      end

      pct = row.pct(field)
      tag.span("#{pct}%", class: class_names('coverage', 'coverage--low' => pct < COVERAGE_LOW))
    end
  end
end
