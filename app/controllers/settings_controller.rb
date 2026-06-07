class SettingsController < ApplicationController
  before_action :set_user

  def show
  end

  def update
    if @user.update(settings_params)
      redirect_to settings_path, notice: t("settings.saved")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = Current.user
  end

  def settings_params
    permitted = params.expect(
      user: [:notification_frequency, :locale, :email_address, :password, :password_confirmation, { location_list: [], style_list: [] }]
    )

    # Blank password means "leave it unchanged" rather than clearing it.
    if permitted[:password].blank?
      permitted.delete(:password)
      permitted.delete(:password_confirmation)
    end

    permitted
  end
end
