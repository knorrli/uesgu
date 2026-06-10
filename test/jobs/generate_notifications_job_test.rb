require 'db_test_helper'

# The job is a thin sweep: seal due digests for every user via
# Notification.generate_for. Verifies it actually creates digests for a due user.
class GenerateNotificationsJobTest < ActiveSupport::TestCase
  test 'perform seals a due digest for a user with new events' do
    user(notification_frequency: 'daily', created_at: 2.days.ago)
    event(created_at: 30.hours.ago) # lands in the first elapsed daily window

    assert_difference -> { Notification.count }, 1 do
      GenerateNotificationsJob.new.perform
    end
  end

  test 'perform creates nothing for a user with notifications off' do
    user(notification_frequency: 'never', created_at: 2.days.ago)
    event(created_at: 30.hours.ago)

    assert_no_difference -> { Notification.count } do
      GenerateNotificationsJob.new.perform
    end
  end
end
