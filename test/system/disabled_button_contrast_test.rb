require "application_system_test_case"

# A browser test because the bug is a cascade outcome, not a declaration: a disabled
# primary got its background from one rule and its text colour from another, and the
# two happened to resolve to the same token — the label was painted in the page
# background and the button read as an empty box. Nothing in either rule looks wrong
# on its own, so only the computed pair catches it.
#
# The styleguide is the target because it specimens every weight in one place.
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
