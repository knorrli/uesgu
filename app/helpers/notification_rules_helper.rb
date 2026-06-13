module NotificationRulesHelper
  # --- form option lists (the schedule, on the new-alert page) ---------------

  def rule_cadence_options
    NotificationRule::CADENCES.map { |c| [t("notification_rules.cadences.#{c}"), c] }
  end

  # Display Monday-first; values are Ruby wday (0=Sun..6=Sat) to match the column.
  def rule_weekday_options
    names = I18n.t("date.day_names")
    [1, 2, 3, 4, 5, 6, 0].map { |wday| [names[wday], wday] }
  end

  def rule_monthday_options
    (1..28).map { |day| [t("notification_rules.monthday_option", day: day), day] }
  end

  # --- alert descriptions (the read-only list + the new-alert preview) -------

  # "Weekly on Friday at 17:30"
  def rule_schedule_summary(rule)
    day_names = I18n.t("date.day_names")
    cadence =
      case rule.cadence
      when "daily"    then t("notification_rules.summary.daily")
      when "weekly"   then t("notification_rules.summary.weekly", day: day_names[rule.weekday.to_i])
      when "biweekly" then t("notification_rules.summary.biweekly", day: day_names[rule.weekday.to_i])
      when "monthly"  then t("notification_rules.summary.monthly", day: rule.monthday)
      end
    t("notification_rules.summary.at_time", cadence: cadence, time: rule.time_string)
  end

  # What the alert is about — the saved filter rendered as text, or live favorites.
  def rule_about(rule)
    return t("notification_rules.favorites_live") if rule.track_favorites?

    parts = []
    parts << rule.style_list.join(", ") if rule.style_list.any?
    parts << rule.location_list.join(", ") if rule.location_list.any?
    parts << rule.queries.join(", ") if rule.queries.any?
    windows = rule.active_windows.map { |w| t("datepicker.#{w}") }
    parts << windows.join(", ") if windows.any?
    parts.any? ? parts.join(" · ") : t("notification_rules.summary.scope_all")
  end

  # "New events" (added) vs "What's on" (happening) — the inferred digest type.
  def rule_type_label(rule)
    rule.happening? ? t("notification_rules.type.happening") : t("notification_rules.type.added")
  end

  # In-app is always present; push/email per rule.
  def rule_channels(rule)
    channels = [t("notification_rules.channels.in_app")]
    channels << t("notification_rules.channels.push") if rule.notify_push?
    channels << t("notification_rules.channels.email") if rule.notify_email?
    channels
  end

  # Reopen this alert's filter on the events page (the "edit" affordance).
  def rule_filter_path(rule)
    events_path(q: rule.queries, l: rule.location_list, s: rule.style_list, d: rule.date_ranges)
  end
end
