class ApplicationMailer < ActionMailer::Base
  default from: MailConfig.from
  layout "mailer"
end
