require "application_system_test_case"

class ZzFieldHeightDiagnosisTest < ApplicationSystemTestCase
  PROBE = <<~JS.freeze
    (() => {
      const fields = Array.from(document.querySelectorAll(".account-form input[type=email], .account-form input[type=password], .account-form select"));
      const select = document.querySelector(".account-form select");
      const s = getComputedStyle(select);
      const input = getComputedStyle(document.querySelector(".account-form input[type=email]"));
      return JSON.stringify({
        heights: fields.map((el) => Math.round(el.getBoundingClientRect().height)),
        ready: document.readyState,
        fonts: Array.from(document.fonts).map((f) => `${f.family}/${f.weight}:${f.status}`).join(" "),
        fontsStatus: document.fonts.status,
        sheets: document.styleSheets.length,
        select: [s.fontFamily, s.fontSize, s.lineHeight, s.paddingTop, s.paddingBottom, s.appearance, s.height, s.transitionProperty, s.transitionDuration].join(" | "),
        input: [input.fontFamily, input.fontSize, input.lineHeight, input.paddingTop].join(" | "),
        bodyClass: document.documentElement.className
      });
    })()
  JS

  test "diagnose" do
    sign_in_as user(locale: "de")
    bad = 0
    30.times do |i|
      visit settings_path
      first = JSON.parse(evaluate_script(PROBE))
      next if first["heights"].uniq.size == 1

      bad += 1
      puts "\nDIAG #{i} FIRST #{first.to_json}"
      evaluate_async_script("document.fonts.ready.then(() => requestAnimationFrame(() => requestAnimationFrame(() => arguments[0](true))))")
      puts "DIAG #{i} AFTER-FONTS #{evaluate_script(PROBE)}"
      sleep 1
      puts "DIAG #{i} AFTER-1S #{evaluate_script(PROBE)}"
    end
    puts "\nDIAG bad=#{bad}/30"
  end
end
