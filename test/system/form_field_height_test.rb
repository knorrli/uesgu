require "application_system_test_case"

# A browser test because the heights come from layout, not from the declarations: a
# field inherits its line-height from whatever it is nested in, so reading the CSS
# cannot tell you two fields ended up different sizes.
class FormFieldHeightTest < ApplicationSystemTestCase
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
end
