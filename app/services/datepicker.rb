class Datepicker
  def self.preset
    # Built fresh per call on purpose: memoizing froze both the locale (labels
    # stuck at the first request's language) and Date.current (dates going stale
    # after midnight). The hash is cheap to recompute.
    {
      today: { label: I18n.t("datepicker.today"), values: [Date.current.iso8601, Date.current.iso8601] },
      tomorrow: { label: I18n.t("datepicker.tomorrow"), values: [Date.current.tomorrow.iso8601, Date.current.tomorrow.iso8601] },
      this_week: { label: I18n.t("datepicker.this_week"), values: [Date.current.beginning_of_week.iso8601, Date.current.end_of_week.iso8601] },
      this_weekend: { label: I18n.t("datepicker.this_weekend"), values: [Date.current.beginning_of_week.next_occurring(:friday).iso8601, Date.current.end_of_week.iso8601] },
      next_week: { label: I18n.t("datepicker.next_week"), values: [Date.current.next_week(:monday).iso8601, Date.current.next_week(:sunday).iso8601] },
      next_weekend: { label: I18n.t("datepicker.next_weekend"), values: [Date.current.next_week(:friday).iso8601, Date.current.next_week(:sunday).iso8601] },
      this_month: { label: I18n.t("datepicker.this_month"), values: [Date.current.beginning_of_month.iso8601, Date.current.end_of_month.iso8601] },
      next_month: { label: I18n.t("datepicker.next_month"), values: [Date.current.beginning_of_month.next_month.iso8601, Date.current.end_of_month.next_month.iso8601] }
    }.with_indifferent_access
  end
end
