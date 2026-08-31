module Admin
  class UsersController < BaseController
    def index
      @users = User.order(created_at: :desc).page(params[:page])
    end

    def show
      @user = User.includes(:sessions, accepted_invitation: :created_by).find(params[:id])
    end

    def toggle_contributor
      @user = User.find(params[:id])
      @user.update!(contributor: !@user.contributor?)

      notice = @user.contributor? ? "admin.users.contributor_granted" : "admin.users.contributor_revoked"
      redirect_to admin_user_path(@user), notice: t(notice, username: @user.username), status: :see_other
    end

    def destroy
      @user = User.find(params[:id])

      if @user == current_user
        redirect_to admin_users_path, alert: t("admin.users.cant_delete_self"), status: :see_other
      else
        username = @user.username
        @user.destroy
        redirect_to admin_users_path, notice: t("admin.users.deleted", username: username), status: :see_other
      end
    end
  end
end
