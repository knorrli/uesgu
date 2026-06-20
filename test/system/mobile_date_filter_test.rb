require "application_system_test_case"

# The When sheet's custom range is a self-contained, client-rendered month
# calendar (range_calendar_controller) in place of the old pair of native date
# inputs. Picking a start day then an end day must write the same
# "YYYY-MM-DD - YYYY-MM-DD" d[] param the server already understands.
class MobileDateFilterTest < ApplicationSystemTestCase
  test "When sheet calendar picks a custom range and applies it as a d[] filter" do
    start_day = Date.current.beginning_of_month + 9  # the 10th — always in-month
    end_day   = Date.current.beginning_of_month + 19 # the 20th
    event(start_date: start_day + 1, genre_list: ["Rock"])

    page.current_window.resize_to(390, 800) # below the 600px sheet breakpoint
    visit events_path

    open_when_sheet
    sheet = ".sheet[data-field=when]"
    # The grid is rendered client-side on connect; wait for its day cells.
    assert_selector "#{sheet} .range-cal__day", minimum: 28

    # Pick start then end. Waiting on the painted is-start/is-end classes avoids
    # racing the click handler (no fixed sleeps).
    find("#{sheet} .range-cal__day[data-date='#{start_day.iso8601}']").click
    assert_selector "#{sheet} .range-cal__day.is-start[data-date='#{start_day.iso8601}']"
    find("#{sheet} .range-cal__day[data-date='#{end_day.iso8601}']").click
    assert_selector "#{sheet} .range-cal__day.is-end[data-date='#{end_day.iso8601}']"

    find("#{sheet} .sheet__apply").click

    # Server-rendered chip + the param in the URL prove the range round-tripped
    # (not just client state). Dates are digits/hyphens, so they aren't re-encoded;
    # the " - " separator between them is, hence the loose middle match.
    assert_current_path(/d%5B%5D=#{start_day.iso8601}.*#{end_day.iso8601}/)
    label = "#{I18n.l(start_day)} - #{I18n.l(end_day)}"
    assert_selector ".filter-sheets__summary .filter-chip", text: label
  end

  private

  # Mirrors mobile_filter_test#open_what_sheet: the controller eager-loads async,
  # so retry the trigger tap until the sheet actually opens (Capybara polls).
  def open_when_sheet
    trigger = find(".filter-sheets .filter-trigger[data-filter-sheets-field-param=when]")
    trigger.click until has_selector?(".sheet[data-field=when].sheet--open", wait: 1)
  end
end
