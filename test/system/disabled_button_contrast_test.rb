require "application_system_test_case"

class DisabledButtonContrastTest < ApplicationSystemTestCase
  test "no disabled button paints its label in its own background" do
    sign_in_as user(admin: true, locale: "de")
    visit styleguide_path

    painted = evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("button[disabled], input[disabled], a.button[disabled]"))
           .map((el) => {
             const style = getComputedStyle(el)
             return { label: el.textContent.trim() || el.value,
                      classes: el.className,
                      same: style.color === style.backgroundColor }
           })
    JS

    assert_operator painted.size, :>=, 4, "expected the styleguide to specimen the disabled weights"
    invisible = painted.select { |button| button["same"] }
    assert_empty invisible, "invisible disabled labels: #{invisible.map { |b| b['classes'] }.inspect}"
  end
end
