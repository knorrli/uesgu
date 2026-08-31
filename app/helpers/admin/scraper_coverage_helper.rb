module Admin
  module ScraperCoverageHelper
    COVERAGE_LOW = 50

    def coverage_cell(row, field)
      return tag.span("—", class: "muted") unless row.present?

      if (reason = row.gap_for(field))
        return tag.span(
          t("admin.scraper_coverage.index.gap"),
          class: "coverage coverage--gap",
          title: t("admin.scraper_coverage.index.gap_reason.#{reason}")
        )
      end

      pct = row.pct(field)
      tag.span("#{pct}%", class: class_names("coverage", "coverage--low" => pct < COVERAGE_LOW))
    end
  end
end
