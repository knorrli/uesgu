module NotificationRulesHelper
  def rule_cadence_options
    NotificationRule::CADENCES.map { |c| [t("notification_rules.cadences.#{c}"), c] }
  end

  def rule_content_type_options
    NotificationRule::CONTENT_TYPES.map { |c| [t("notification_rules.content_types.#{c}"), c] }
  end

  def rule_scope_options
    NotificationRule::SCOPES.map { |s| [t("notification_rules.scopes.#{s}"), s] }
  end

  def rule_window_options
    NotificationRule::WINDOWS.map { |w| [t("datepicker.#{w}"), w] }
  end

  # Display Monday-first; values are Ruby wday (0=Sun..6=Sat) to match the column.
  def rule_weekday_options
    names = I18n.t("date.day_names")
    [1, 2, 3, 4, 5, 6, 0].map { |wday| [names[wday], wday] }
  end

  def rule_monthday_options
    (1..28).map { |day| [t("notification_rules.monthday_option", day: day), day] }
  end

  # Human one-liner describing what a rule does, for the rule list.
  def rule_summary(rule)
    [cadence_phrase(rule), content_phrase(rule), scope_phrase(rule)].compact.join(" · ")
  end

  # The channels a rule delivers on, as short labels (in-app is always present).
  def rule_channels(rule)
    channels = [t("notification_rules.channels.in_app")]
    channels << t("notification_rules.channels.push") if rule.notify_push?
    channels << t("notification_rules.channels.email") if rule.notify_email?
    channels
  end

  private

  def cadence_phrase(rule)
    day_names = I18n.t("date.day_names")
    base =
      case rule.cadence
      when "daily"    then t("notification_rules.summary.daily")
      when "weekly"   then t("notification_rules.summary.weekly", day: day_names[rule.weekday.to_i])
      when "biweekly" then t("notification_rules.summary.biweekly", day: day_names[rule.weekday.to_i])
      when "monthly"  then t("notification_rules.summary.monthly", day: rule.monthday)
      end
    t("notification_rules.summary.at_time", cadence: base, time: rule.time_string)
  end

  def content_phrase(rule)
    if rule.happening?
      t("notification_rules.summary.happening", window: t("datepicker.#{rule.window}"))
    else
      t("notification_rules.summary.added")
    end
  end

  def scope_phrase(rule)
    case rule.scope
    when "all"       then t("notification_rules.summary.scope_all")
    when "favorites" then t("notification_rules.summary.scope_favorites")
    when "custom"    then custom_scope_phrase(rule)
    end
  end

  def custom_scope_phrase(rule)
    bits = []
    bits << Array(rule.filter["style_list"]).join(", ") if rule.filter["style_list"].present?
    bits << Array(rule.filter["location_list"]).join(", ") if rule.filter["location_list"].present?
    bits << Array(rule.filter["queries"]).join(", ") if rule.filter["queries"].present?
    bits.any? ? t("notification_rules.summary.scope_custom", detail: bits.join(" / ")) : t("notification_rules.scopes.custom")
  end
end
