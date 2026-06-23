module Admin
  # Mint and manage single-use invite codes — the only way to create an account.
  class InvitationsController < BaseController
    def index
      load_invitations
      @invitation = Invitation.new
    end

    def create
      @invitation = Invitation.new(
        created_by: current_user,
        note: invitation_params[:note].presence,
        expires_at: expires_at_from(invitation_params[:expires_in_days])
      )

      if @invitation.save
        redirect_to admin_invitations_path, notice: t("admin.invitations.created", code: @invitation.formatted_code)
      else
        load_invitations
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      invitation = Invitation.find(params[:id])

      if invitation.redeemed?
        redirect_to admin_invitations_path, alert: t("admin.invitations.cant_revoke_redeemed"), status: :see_other
      else
        invitation.destroy
        redirect_to admin_invitations_path, notice: t("admin.invitations.revoked"), status: :see_other
      end
    end

    private

    def load_invitations
      @invitations = Invitation.includes(:created_by, :redeemed_by).order(created_at: :desc)
    end

    def invitation_params
      params.fetch(:invitation, {}).permit(:note, :expires_in_days)
    end

    # Expiry is offered as a small set of day presets ('' = unlimited) to keep
    # the form dead simple and dodge timezone/date-parsing footguns.
    def expires_at_from(days)
      days.present? ? days.to_i.days.from_now : nil
    end
  end
end
