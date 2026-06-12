# Proactively seals due notification digests for every user, so the unread count
# is populated (and push can fire) without the user visiting /notifications first.
# Notification.generate_for is a no-op for users with no period due, so this is
# safe to run daily.
class GenerateNotificationsJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each do |user|
      created = Notification.generate_for(user)
      # Fan the just-sealed digests out to the user's devices. Done here rather
      # than inside generate_for so the lazy page-load path (which also calls
      # generate_for) never triggers a push — only this background sweep does.
      WebPushNotifier.deliver_digests(user, created) if created.any?
    end
  end
end
