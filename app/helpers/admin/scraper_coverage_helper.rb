module Admin
  module ScraperCoverageHelper
    # Below this fill-rate, a cell is flagged for a look: either the scraper could
    # be collecting more, or its extractor broke. (Not green — green is reserved
    # for "interested"; this is an attention state, so it uses the warn colour.)
    COVERAGE_LOW = 50

    # One fill-rate cell. Em dash when the scraper has no events to measure;
    # otherwise the percentage, flagged --low when too many events lack the field.
    def coverage_cell(row, pct)
      return tag.span('—', class: 'muted') unless row.present?

      tag.span("#{pct}%", class: class_names('coverage', 'coverage--low' => pct < COVERAGE_LOW))
    end
  end
end
