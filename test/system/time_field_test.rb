require "application_system_test_case"

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
    assert_text "Manuelle Überschreibungen" #
    assert_nil e.reload.start_time
  end

  test "the clear button stays away until the field holds a time" do
    e = event(start_date: Date.current + 3)
    sign_in_as user(admin: true, locale: "de")
    visit admin_event_path(e)

    assert_no_selector ".time-field__clear", visible: true
    execute_script("const i = document.querySelector('#event_time');" \
                   "i.value = '21:00'; i.dispatchEvent(new Event('input'))")
    assert_selector ".time-field__clear", visible: true
  end
end
