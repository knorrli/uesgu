module Admin
  # Account moderation: list, inspect, and delete (spam) accounts.
  class UsersController < BaseController
    def index
      @users = User.order(created_at: :desc).page(params[:page])
    end

    def show
      @user = User.includes(:sessions, accepted_invitation: :created_by).find(params[:id])
    end

    def destroy
      @user = User.find(params[:id])

      # The only guard needed: you can't delete yourself. Since self-deletion is
      # always refused, at least one admin (you) always remains — there's no way
      # to lock the site out of its admin via this screen.
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
