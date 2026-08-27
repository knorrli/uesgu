require "application_system_test_case"

# The start time sits in a gutter of its own, so an event whose time is unknown has
# to indent exactly like the timed rows around it — including where a whole venue
# group is untimed. Browser-driven because the indent comes from a grid track
# resolving against the row's own font, which reading the CSS cannot settle.
class EventRowGeometryTest < ApplicationSystemTestCase
  test "a title starts at the same edge whether or not the event has a time" do
    day = Date.current + 2
    event(title: "Timed show", start_date: day,
          start_time: Time.zone.local(day.year, day.month, day.day, 20, 0))
    event(title: "Untimed show", start_date: day)

    sign_in_as user
    visit events_path
    page.current_window.resize_to(393, 852)
    assert_selector ".event-title", count: 2

    lefts = evaluate_script(
      "Array.from(document.querySelectorAll('.event-title'))" \
      ".map((el) => Math.round(el.getBoundingClientRect().left))"
    )

    assert_equal 1, lefts.uniq.size, "title left edges differ: #{lefts.inspect}"
  end
end
