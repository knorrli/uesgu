# Proactively seals due notification digests for every user, so the unread count
# is populated (and push can fire) without the user visiting /notifications first.
# Notification.generate_for is a no-op for users with no period due, so this is
# safe to run daily.
class GenerateNotificationsJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each do |user|
      Notification.generate_for(user)
    end
  end
end
