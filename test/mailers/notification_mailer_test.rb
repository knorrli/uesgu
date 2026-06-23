require "db_test_helper"

# Locks the digest email: right recipient/subject, the events rendered inline,
# the event's own link, and a CTA back to the in-app notification page. Runs in
# :test delivery (see config/initializers/mail.rb) so nothing hits Resend.
class NotificationMailerTest < ActionMailer::TestCase
  test "digest addresses the user, lists events, and links to the in-app page" do
    u = user(email_address: "fan@example.test", locale: "de")
    show = event(start_date: Date.current + 2, url: "https://venue.test/show")
    note = u.notifications.create!(title: "Wochen-Digest", event_ids: [show.id],
                                   period_start: 1.week.ago, period_end: Time.current)

    mail = NotificationMailer.digest(note)

    assert_equal ["fan@example.test"], mail.to
    assert_match "üsgu", mail.subject

    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s
    assert_match show.title, html
    assert_match "https://venue.test/show", html        # the event's own link
    assert_match "/notifications/#{note.id}", html       # CTA to the in-app page
    assert_match show.title, text
  end

  test "the heading renders in the recipient locale, not the frozen-title locale" do
    u = user(email_address: "fan4@example.test", locale: "en")
    # The rule's name freezes under the test's default locale (de): "… · Neue Events".
    rule = u.saved_filters.new(cadence: "daily", time_of_day: 600,
                                    notify_push: false, notify_email: false)
    rule.filter_attributes = { q: ["Rock"] }
    rule.save!
    assert_match "Neue Events", rule.name, "name is frozen in de here"

    ev = event(start_date: Date.current + 2)
    note = u.notifications.create!(saved_filter: rule, title: rule.name,
                                   event_ids: [ev.id], period_start: 1.week.ago, period_end: Time.current)

    html = NotificationMailer.digest(note).html_part.body.to_s
    assert_match "New events", html, "heading re-derived in the user locale (en)"
    assert_no_match(/Neue Events/, html, "not the de-frozen title")
  end

  test "a non-http event url is not turned into a link" do
    u = user(email_address: "fan3@example.test", locale: "de")
    # Scraped data can be malformed; such a value must never become an href.
    show = event(start_date: Date.current + 2, title: "Sketchy Show", url: "javascript:alert(1)")
    note = u.notifications.create!(title: "D", event_ids: [show.id],
                                   period_start: 1.week.ago, period_end: Time.current)

    html = NotificationMailer.digest(note).html_part.body.to_s
    assert_match "Sketchy Show", html, "the title still shows"
    assert_no_match(/href="javascript:/, html, "but not as a link")
  end

  test "ships a dark-mode variant: both logo grounds embed and the media query is present" do
    u = user(email_address: "fan5@example.test", locale: "de")
    ev = event(start_date: Date.current + 2)
    note = u.notifications.create!(title: "D", event_ids: [ev.id],
                                   period_start: 1.week.ago, period_end: Time.current)

    mail = NotificationMailer.digest(note)
    names = mail.all_parts.map(&:filename).compact
    assert_includes names, "uesgu-icon.png", "light (cream-ground) mark embedded"
    assert_includes names, "uesgu-icon-dark.png", "dark (plum-ground) mark embedded"

    html = mail.html_part.body.to_s
    assert_match "prefers-color-scheme: dark", html, "dark media query ships"
    assert_match 'content="light dark"', html, "both schemes declared so clients honor the query"
  end

  test "subject pluralizes with the event count" do
    u = user(email_address: "fan2@example.test", locale: "en")
    e1 = event(start_date: Date.current + 1)
    e2 = event(start_date: Date.current + 2)
    note = u.notifications.create!(title: "D", event_ids: [e1.id, e2.id],
                                   period_start: 1.week.ago, period_end: Time.current)

    assert_match "2 new events", NotificationMailer.digest(note).subject
  end
end
