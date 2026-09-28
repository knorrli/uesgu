module ActionLogsHelper
  def action_log_actor(entry)
    entry.user&.username || t("admin.action_logs.deleted_account")
  end

  def action_log_sentence(entry)
    subject = action_log_subject(entry)
    return t("admin.action_logs.sentences.undo_html", actor: action_log_actor(entry.reverts), subject: subject) if entry.undo?

    t("admin.action_logs.sentences.#{entry.action.tr('.', '_')}_html", subject: subject, **entry.details.symbolize_keys)
  end

  def action_log_subject(entry)
    return entry.subject_label unless entry.subject.is_a?(Event)

    link_to entry.subject_label, admin_event_path(entry.subject)
  end
end
