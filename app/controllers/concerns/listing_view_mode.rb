# List vs calendar view persistence, shared by the main programme (EventsController)
# and the saved-shows list (SavedEventsController). Each listing keeps its own
# choice under its own session key + account column.
module ListingViewMode
  extend ActiveSupport::Concern

  private

  # Resolve the chosen view and remember it across requests (filter changes,
  # pagination, month nav) until the visitor explicitly switches again. Session
  # is the primary store; for a logged-in user we also mirror it onto their
  # account so the preference follows them to a fresh session / another device.
  # Only an explicit ?view= switch writes to the account — a plain GET render
  # (the hot path) never writes.
  def resolve_view(session_key:, account_attr:)
    view = params[:view].presence || session[session_key] || current_user&.public_send(account_attr) || "list"
    view = "list" unless view == "calendar"
    session[session_key] = view
    if params[:view].present? && current_user && current_user.public_send(account_attr) != view
      current_user.update_column(account_attr, view)
    end
    view
  end
end
