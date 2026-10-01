class SettingsController < ApplicationController
  before_action :set_user
  helper_method :excluded_genres, :excluded_locations

  def show
  end

  def update
    if @user.update(settings_params)
      set_locale
      redirect_to settings_path, notice: t("settings.saved")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = Current.user
  end

  def excluded_genres
    Genre.where(id: Exclusions.for(@user).genre_roots).by_name
  end

  def excluded_locations
    @user.location_exclusions.order(:name)
  end

  def settings_params
    permitted = params.expect(
      user: [:locale, :email_address, :password, :password_confirmation]
    )

    if permitted[:password].blank?
      permitted.delete(:password)
      permitted.delete(:password_confirmation)
    end

    permitted
  end
end
