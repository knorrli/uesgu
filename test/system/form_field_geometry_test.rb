require "application_system_test_case"

class FormFieldGeometryTest < ApplicationSystemTestCase
  FIELDS = ".account-form input[type=email], .account-form input[type=password], .account-form select".freeze

  test "every field in the account-form skin is the same height" do
    sign_in_as user(locale: "de")
    visit settings_path

    heights = evaluate_script(
      "Array.from(document.querySelectorAll(#{FIELDS.inspect}))" \
      ".map((el) => Math.round(el.getBoundingClientRect().height))"
    )

    assert_operator heights.size, :>=, 3, "expected the settings form to carry a select and inputs"
    assert_equal 1, heights.uniq.size, "field heights differ: #{heights.inspect}"
  end

  PICKERS = "#event_date, #event_time, #event_description".freeze

  test "the date and time pickers are the height of the text fields beside them" do
    sign_in_as user(admin: true, locale: "de")
    visit admin_event_path(event)

    heights = evaluate_script(
      "Array.from(document.querySelectorAll(#{PICKERS.inspect}))" \
      ".map((el) => Math.round(el.getBoundingClientRect().height))"
    )

    assert_equal 3, heights.size, "expected a date, a time and a text field on the event editor"
    assert_equal 1, heights.uniq.size, "field heights differ: #{heights.inspect}"
  end

  test "the date and time pair spans the row it shares" do
    sign_in_as user(admin: true, locale: "de")
    visit admin_event_path(event)
    page.current_window.resize_to(390, 844)

    row, date, time = evaluate_script(
      "['.account-form .flex.wrap', '#event_date', '#event_time']" \
      ".map((sel) => document.querySelector(sel).getBoundingClientRect().toJSON())"
    )

    assert_in_delta row["left"], date["left"], 1
    assert_in_delta row["right"], time["right"], 1
  end
end
