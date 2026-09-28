module Admin
  class ActionLogsController < BaseController
    include CatalogueBrowsing

    def index
      @entries = ActionLog.newest_first.includes(:user, :subject, reverts: :user, reversal: :user)
                          .page(params[:page]).per(PAGE_SIZE)
    end

    def undo
      ActionLog.find(params.expect(:id)).undo!
      redirect_to admin_action_logs_path, notice: t(".undone"), status: :see_other
    rescue ArgumentError
      redirect_to admin_action_logs_path, alert: t(".stale"), status: :see_other
    end
  end
end
