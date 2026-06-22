require "application_system_test_case"

# Regression for a Turbo Drive scroll bug (worked around in app/javascript/application.js).
#
# Opening a day in the calendar is a turbo-frame navigation with
# data-turbo-action="advance" (app/views/events/_calendar.html.erb). That promotes
# to a page-level visit which updates history WITHOUT re-rendering the page, and on
# that no-render path Turbo sets the page View's internal `forceReloaded` flag and
# never clears it. While the flag is set, Turbo skips its scroll reset on EVERY
# later Drive visit — so paging the feed silently stops scrolling to the top.
#
# Without the workaround this test fails: after opening a calendar day, the "next"
# click lands mid-page (at the new page's clamped scroll) instead of at the top.
class FeedPaginationScrollTest < ApplicationSystemTestCase
  test "feed pagination scrolls to top even after a calendar day was opened" do
    # Enough for the "next" click to land on a FULL second page (default_per_page =
    # 25): page 2 must be tall enough to stay scrolled, otherwise the browser's own
    # clamp to a short page would mask a missing scroll-to-top. All on one day so the
    # calendar has a populated, clickable cell to open.
    55.times { event(start_date: Date.new(2030, 1, 1)) }

    visit events_path
    assert_selector ".pagination__step[rel=next]" # precondition: the feed is paginated

    # The fixed cookie notice sits over the bottom of the page; dismiss it so it
    # can't intercept the "next" click once we've scrolled down.
    find(".cookie-notice [data-action~='cookie-notice#dismiss']").click
    assert_no_selector ".cookie-notice", visible: true

    # Poison Turbo's scroll state: calendar → open a day (frame-advance visit) →
    # close it → back to the list. (href selectors — the test UI renders in English.)
    find("a[href*='view=calendar']").click
    find(".calendar-day-link", match: :first).click
    assert_selector ".calendar-day-link.selected"  # day opened (frame re-rendered)
    find(".calendar-day-link.selected").click       # close it
    find("a[href*='view=list']").click
    assert_selector ".pagination__step[rel=next]"  # back on the paginated list

    # Scroll to the bottom, then page forward.
    execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
    assert_operator current_scroll_y, :>, 100, "precondition: should be scrolled down the page"

    find(".pagination__step[rel=next]").click
    assert_current_path(/page=2/)

    assert_scrolled_to_top
  end

  private

  def current_scroll_y
    evaluate_script("Math.round(window.scrollY)").to_i
  end

  # No-sleep wait: retry reading the scroll position until Turbo has reset it to the
  # top (its reset fires a tick after the snapshot renders), within Capybara's wait.
  def assert_scrolled_to_top
    page.document.synchronize(Capybara.default_max_wait_time, errors: [RuntimeError]) do
      y = current_scroll_y
      raise "expected the page scrolled to the top, but it was at #{y}px" unless y <= 5
    end
    assert true
  end
end
