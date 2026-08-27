require "application_system_test_case"

# The inbox at the narrowest viewport we still support (320px — iPhone SE 1st gen,
# Galaxy Fold cover screen).
class InboxNarrowViewportTest < ApplicationSystemTestCase
  # .notification__meta is nowrap so the date range stays flush right, and it used to
  # shove the whole page wider than the viewport. Locale matters, and French is the
  # widest of the three ("3 événements"), so it is the one that has to fit.
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
