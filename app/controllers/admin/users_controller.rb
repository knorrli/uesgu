module Admin
  class UsersController < BaseController
    def index
      @users = User.order(created_at: :desc).page(params[:page])
    end

    def show
      @user = User.includes(:sessions, accepted_invitation: :created_by).find(params[:id])
      @captured_events = @user.captured_events.order(created_at: :desc)
    end

    def permissions
      @user = User.find(params[:id])
      wanted = Array(params.dig(:user, :permissions)).map(&:to_s) & User::PERMISSIONS
      User.transaction do
        (wanted - @user.permissions).each { |permission| log_permission("user.grant_permission", permission) }
        (@user.permissions - wanted).each { |permission| log_permission("user.revoke_permission", permission) }
        @user.update!(permissions: wanted)
      end
      redirect_to admin_user_path(@user), notice: t("admin.users.permissions_saved", username: @user.username),
                                          status: :see_other
    end

    def destroy
      @user = User.find(params[:id])

      if @user == current_user
        redirect_to admin_users_path, alert: t("admin.users.cant_delete_self"), status: :see_other
      else
        username = @user.username
        ActionLog.track("user.delete", @user) { @user.destroy! }
        redirect_to admin_users_path, notice: t("admin.users.deleted", username: username), status: :see_other
      end
    end

    private

    def log_permission(action, permission)
      ActionLog.record!(action, @user, permission: permission)
    end
  end
end
