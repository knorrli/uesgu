require "application_system_test_case"

# The inbox at the narrowest viewport we still support (320px — iPhone SE 1st gen,
# Galaxy Fold cover screen).
class InboxNarrowViewportTest < ApplicationSystemTestCase
  # .notification__meta is nowrap so the date range stays flush right, and it used to
  # shove the whole page ~29px wider than the viewport. Locale matters: the overflow
  # only shows in German ("3 Veranstaltungen" is far wider than "3 events"), which is
  # the default locale but NOT what a headless browser's Accept-Language asks for.
  test "the inbox does not scroll horizontally at 320px" do
    u = user(locale: "de")
    events = 3.times.map { event(start_date: Date.new(2026, 8, 8)) }
    Notification.create!(user: u, title: "Rock in Bern",
      period_start: Date.new(2026, 8, 6), period_end: Date.new(2026, 8, 13),
      event_ids: events.map(&:id))

    page.current_window.resize_to(320, 800)
    sign_in_as(u)
    visit notifications_path

    assert_selector ".notification__meta", text: "3 Veranstaltungen"
    assert_equal evaluate_script("window.innerWidth"),
      evaluate_script("document.documentElement.scrollWidth")
  end
end
