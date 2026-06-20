class SettingsController < ApplicationController
  before_action :set_user

  def show
  end

  def update
    if @user.update(settings_params)
      # Re-evaluate the locale from the just-saved preference so the flash is in
      # the newly chosen language (set_locale ran before the update).
      set_locale
      redirect_to settings_path, notice: t('settings.saved')
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = Current.user
  end

  def settings_params
    # event_reminders moved to the saved-shows page (SavedEventsController#reminders),
    # so it's no longer part of the Settings form.
    permitted = params.expect(
      user: [:locale, :email_address, :password, :password_confirmation]
    )

    # Blank password means "leave it unchanged" rather than clearing it.
    if permitted[:password].blank?
      permitted.delete(:password)
      permitted.delete(:password_confirmation)
    end

    permitted
  end
end
