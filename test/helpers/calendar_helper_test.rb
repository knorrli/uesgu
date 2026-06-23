require "db_test_helper"

# Locks CalendarHelper#calendar_day_headline — the per-cell relevance headline: up
# to two venues of the day's SAVED events, plus a "+N more" overflow count.
# Synthetic location names (not real venues, so `venue` falls back to the first
# location tag — deterministic and scraper-independent).
class CalendarHelperTest < ActionView::TestCase
  # calendar_day_headline leans on EventsHelper (event_saved?); in the app every
  # helper shares one view context, so pull it in here too.
  include EventsHelper

  # Saved state is read via the EventsHelper memo ivar, so we seed it directly
  # instead of standing up a session + current_user.

  test "headline names up to two saved venues and spills the rest into extra" do
    saved = [
      event(location_list: ["Aula"]),
      event(location_list: ["Beisl"]),
      event(location_list: ["Cano"]),
      event(location_list: ["Cano"]) # duplicate venue collapses, not counted twice
    ]
    @saved_event_ids = Set.new(saved.map(&:id))

    headline = calendar_day_headline(saved)

    assert_equal %w[Aula Beisl], headline.venues
    assert_equal 1, headline.extra, "three distinct venues → two named + 1 more"
  end

  test "headline has no overflow when two or fewer saved venues" do
    saved = [event(location_list: ["Aula"]), event(location_list: ["Beisl"])]
    @saved_event_ids = Set.new(saved.map(&:id))

    headline = calendar_day_headline(saved)

    assert_equal %w[Aula Beisl], headline.venues
    assert_equal 0, headline.extra
  end

  test "only saved events headline; unsaved ones are ignored" do
    saved = event(location_list: ["Aula"])
    unsaved = event(location_list: ["Ignored"])
    @saved_event_ids = Set.new([saved.id])

    headline = calendar_day_headline([saved, unsaved])

    assert_equal ["Aula"], headline.venues
    assert_equal 0, headline.extra
  end

  test "headline is nil on a day with no saved events" do
    @saved_event_ids = Set.new

    assert_nil calendar_day_headline([event(location_list: ["Aula"])])
  end
end
