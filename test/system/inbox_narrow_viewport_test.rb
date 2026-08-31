require "application_system_test_case"

class InboxNarrowViewportTest < ApplicationSystemTestCase
  test "the inbox does not scroll horizontally at 320px" do
    u = user(locale: "fr")
    events = 3.times.map { event(start_date: Date.new(2026, 8, 8)) }
    Notification.create!(user: u, title: "Rock in Bern",
      period_start: Date.new(2026, 8, 6), period_end: Date.new(2026, 8, 13),
      event_ids: events.map(&:id))

    page.current_window.resize_to(320, 800)
    sign_in_as(u)
    visit notifications_path

    assert_selector ".notification__meta", text: "3 événements"
    assert_equal evaluate_script("window.innerWidth"),
      evaluate_script("document.documentElement.scrollWidth")
  end
end
