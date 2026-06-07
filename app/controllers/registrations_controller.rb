class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_url, alert: t("auth.rate_limited") }

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      start_new_session_for @user
      redirect_to root_path, notice: t("registrations.welcome")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Delete own account.
  def destroy
    user = Current.user
    terminate_session
    user.destroy
    redirect_to root_path, notice: t("registrations.account_deleted"), status: :see_other
  end

  private

  def registration_params
    params.expect(user: %i[ username password password_confirmation notification_frequency ])
  end
end
