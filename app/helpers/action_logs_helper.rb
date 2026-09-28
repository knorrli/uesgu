module ActionLogsHelper
  def action_log_actor(entry)
    entry.user&.username || t("admin.action_logs.deleted_account")
  end

  def action_log_sentence(entry)
    subject = action_log_subject(entry)
    return t("admin.action_logs.sentences.undo_html", actor: action_log_actor(entry.reverts), subject: subject) if entry.undo?

    t("admin.action_logs.sentences.#{entry.action.tr('.', '_')}_html", subject: subject, **entry.details.symbolize_keys)
  end

  ACTION_LOG_SUBJECT_PATHS = {
    "Event" => :admin_event_path, "Genre" => :edit_genre_path, "Place" => :edit_admin_place_path,
    "Locality" => :edit_admin_locality_path, "User" => :admin_user_path, "ScrapeRun" => :admin_scrape_run_path
  }.freeze

  def action_log_subject(entry)
    path = ACTION_LOG_SUBJECT_PATHS[entry.subject_type]
    return entry.subject_label unless path && entry.subject

    link_to entry.subject_label, public_send(path, entry.subject)
  end
end
