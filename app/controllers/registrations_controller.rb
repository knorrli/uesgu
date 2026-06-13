class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_url, alert: t('auth.rate_limited') }

  def new
    @user = User.new
    @invite_code = submitted_invite_code
  end

  # Invitation-only: a valid, unredeemed code is required to create an account.
  # The user and the redemption are committed together, so a failure on either
  # side (taken username, or the code lost a race) leaves nothing behind.
  def create
    @user = User.new(registration_params)
    @invite_code = submitted_invite_code
    invitation = Invitation.available_by_code(@invite_code)

    if invitation.nil?
      @user.errors.add(:base, t('registrations.invalid_invite'))
      return render :new, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      @user.save!
      invitation.redeem!(@user)
    end

    start_new_session_for @user
    redirect_to root_path, notice: t('registrations.welcome')
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  rescue Invitation::Unavailable
    @user.errors.add(:base, t('registrations.invalid_invite'))
    render :new, status: :unprocessable_entity
  end

  # Delete own account.
  def destroy
    user = Current.user
    terminate_session
    user.destroy
    redirect_to root_path, notice: t('registrations.account_deleted'), status: :see_other
  end

  private

  def registration_params
    params.expect(user: %i[ username password password_confirmation ])
  end

  # The code typed into the form (create / failed re-render) or carried in the
  # shareable signup link (?invite=…).
  def submitted_invite_code
    params[:invitation_code].presence || params[:invite]
  end
end
