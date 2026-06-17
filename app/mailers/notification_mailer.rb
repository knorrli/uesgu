class NotificationMailer < ApplicationMailer
  # The self-contained digest email: the actual events inline (so it reads
  # without clicking through) PLUS a button back to the in-app notification page.
  # Push, by contrast, is just a blurb that deep-links there.
  def digest(notification)
    @notification = notification
    @user = notification.user
    @rule = notification.notification_rule
    @events = notification.events.includes(:locations, :styles, :genres).to_a
    @notification_url = notification_url(@notification)
    @browse_url = root_url

    I18n.with_locale(@user.locale.presence || I18n.default_locale) do
      # Render the heading in the recipient's locale rather than reusing the title
      # frozen at fire time (which carries whatever locale was active when the rule
      # was last saved) — otherwise a digest body and its heading could disagree.
      # deliver_later runs within seconds of firing, so describe still matches the
      # snapshot; fall back to the frozen title for any rule-less notification.
      @heading = @rule ? @rule.describe : @notification.title
      mail(to: @user.email_address, subject: t("notification_mailer.digest.subject", count: @events.size))
    end
  end
end
