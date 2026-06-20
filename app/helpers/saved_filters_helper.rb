module SavedFiltersHelper
  # --- form option lists (the schedule, on the new-alert page) ---------------

  def rule_cadence_options
    SavedFilter::CADENCES.map { |c| [t("saved_filters.cadences.#{c}"), c] }
  end

  # Display Monday-first; values are Ruby wday (0=Sun..6=Sat) to match the column.
  def rule_weekday_options
    names = I18n.t("date.day_names")
    [1, 2, 3, 4, 5, 6, 0].map { |wday| [names[wday], wday] }
  end

  def rule_monthday_options
    (1..28).map { |day| [t("saved_filters.monthday_option", day: day), day] }
  end

  # The relative windows offerable on a rule (blank = none → "new events"). Only
  # presets — a rule never takes an absolute range (see SavedFilter).
  def rule_window_options
    SavedFilter::WINDOW_RHYTHM.keys.map { |key| [t("datepicker.#{key}"), key] }
  end

  # The notification time, split into two selects (see SavedFilter#time_hour). The
  # minute list is only the quarter hours the scheduler can honour, so the time can
  # never be set to a value that would silently snap.
  def rule_time_hour_options = (0..23).map { |h| format("%02d", h) }

  def rule_time_minute_options = %w[00 15 30 45]

  # --- alert descriptions (the read-only list + the new-alert preview) -------

  # "Weekly on Friday at 17:30"
  def rule_schedule_summary(rule)
    day_names = I18n.t("date.day_names")
    cadence =
      case rule.cadence
      when "daily"    then t("saved_filters.summary.daily")
      when "weekly"   then t("saved_filters.summary.weekly", day: day_names[rule.weekday.to_i])
      when "biweekly" then t("saved_filters.summary.biweekly", day: day_names[rule.weekday.to_i])
      when "monthly"  then t("saved_filters.summary.monthly", day: rule.monthday)
      end
    t("saved_filters.summary.at_time", cadence: cadence, time: rule.time_string)
  end

  # In-app is always present; push/email per rule.
  def rule_channels(rule)
    channels = [t("saved_filters.channels.in_app")]
    channels << t("saved_filters.channels.push") if rule.notify_push?
    channels << t("saved_filters.channels.email") if rule.notify_email?
    channels
  end
end
