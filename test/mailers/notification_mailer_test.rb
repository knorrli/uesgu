require 'db_test_helper'

# Locks the digest email: right recipient/subject, the events rendered inline,
# the event's own link, and a CTA back to the in-app notification page. Runs in
# :test delivery (see config/initializers/mail.rb) so nothing hits Resend.
class NotificationMailerTest < ActionMailer::TestCase
  test 'digest addresses the user, lists events, and links to the in-app page' do
    u = user(email_address: 'fan@example.test', locale: 'de')
    show = event(start_date: Date.current + 2, url: 'https://venue.test/show')
    note = u.notifications.create!(title: 'Wochen-Digest', event_ids: [show.id],
                                   period_start: 1.week.ago, period_end: Time.current)

    mail = NotificationMailer.digest(note)

    assert_equal ['fan@example.test'], mail.to
    assert_match 'üsgu', mail.subject

    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s
    assert_match show.title, html
    assert_match 'https://venue.test/show', html        # the event's own link
    assert_match "/notifications/#{note.id}", html       # CTA to the in-app page
    assert_match show.title, text
  end

  test 'subject pluralizes with the event count' do
    u = user(email_address: 'fan2@example.test', locale: 'en')
    e1 = event(start_date: Date.current + 1)
    e2 = event(start_date: Date.current + 2)
    note = u.notifications.create!(title: 'D', event_ids: [e1.id, e2.id],
                                   period_start: 1.week.ago, period_end: Time.current)

    assert_match '2 new events', NotificationMailer.digest(note).subject
  end
end
