require "application_system_test_case"

# The only way to enter "this event's start time is unknown": no engine lets you clear
# a native time control, so the field carries a ✕ of its own (shared/_time_field).
class TimeFieldTest < ApplicationSystemTestCase
  test "clearing the time saves the event as untimed" do
    day = Date.current + 3
    e = event(start_date: day, start_time: Time.zone.local(day.year, day.month, day.day, 20, 30))
    sign_in_as user(admin: true, locale: "de")
    visit admin_event_path(e)

    assert_equal "20:30", find("#event_time").value
    find(".time-field__clear").click
    assert_equal "", find("#event_time").value

    find("input[type=submit]").click
    assert_text "Manuelle Überschreibungen" # the locked-fields section, which only a saved edit renders
    assert_nil e.reload.start_time
  end

  test "the clear button stays away until the field holds a time" do
    e = event(start_date: Date.current + 3)
    sign_in_as user(admin: true, locale: "de")
    visit admin_event_path(e)

    assert_no_selector ".time-field__clear", visible: true
    # Set through the DOM: typing into a native time control means driving whichever
    # segment layout the engine happens to lay out, which is not what this asserts.
    execute_script("const i = document.querySelector('#event_time');" \
                   "i.value = '21:00'; i.dispatchEvent(new Event('input'))")
    assert_selector ".time-field__clear", visible: true
  end
end
