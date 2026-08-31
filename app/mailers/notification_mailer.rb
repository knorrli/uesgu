class NotificationMailer < ApplicationMailer
  def digest(notification)
    @notification = notification
    @user = notification.user
    @rule = notification.saved_filter
    @events = notification.events.includes(:locations, :genres).to_a
    @notification_url = notification_url(@notification)
    @browse_url = root_url

    attachments.inline["uesgu-icon.png"] = File.binread(Rails.root.join("public/email-icon-light.png"))
    attachments.inline["uesgu-icon-dark.png"] = File.binread(Rails.root.join("public/email-icon-dark.png"))

    I18n.with_locale(@user.locale.presence || I18n.default_locale) do
      @heading = @rule ? @rule.describe : @notification.title
      mail(to: @user.email_address, subject: t("notification_mailer.digest.subject", count: @events.size))
    end
  end
end
