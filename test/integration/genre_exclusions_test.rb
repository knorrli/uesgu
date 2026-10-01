require "db_test_helper"

class GenreExclusionsTest < ActionDispatch::IntegrationTest
  setup do
    @hated = genre(name: "Exhated")
    @liked = genre(name: "Exliked")
    @mixed = event_with_genres(@hated.name, @liked.name).tap { |e| e.update!(title: "MixedMarkerShow") }
    @clean = event_with_genres(@liked.name).tap { |e| e.update!(title: "CleanMarkerShow") }
  end

  test "signed out, the feed shows everything and offers no exclude button" do
    get events_path

    assert_includes response.body, "MixedMarkerShow"
    assert_select "form[action=?]", genre_exclusions_path, false
    assert_select ".day-summary__count--excluded", false
  end

  test "excluding requires an account" do
    post genre_exclusions_path, params: { name: @hated.name }

    assert_redirected_to new_session_path
    assert_equal 0, GenreExclusion.count
  end

  test "every genre tag on the feed carries an exclude button for a signed-in user" do
    sign_in_as user

    get events_path

    assert_select "##{dom_id(@mixed)} .event-genre form[action=?]", genre_exclusions_path, count: 2
  end

  test "excluding a genre takes effect at once and returns to the page it was pressed on" do
    listener = sign_in_as user
    feed = events_path(g: [@liked.name], filtered: 1)

    post genre_exclusions_path, params: { name: @hated.name, return_to: feed }

    assert_redirected_to feed
    assert_equal [@hated], listener.genre_exclusions.map(&:genre)
  end

  test "excluding an alias stores its canonical" do
    listener = sign_in_as user
    variant = genre(name: "Exvariant")
    variant.merge_into!(@hated)

    post genre_exclusions_path, params: { name: variant.name }

    assert_equal [@hated], listener.genre_exclusions.map(&:genre)
  end

  test "excluding the same genre twice keeps one exclusion" do
    listener = sign_in_as user

    2.times { post genre_exclusions_path, params: { name: @hated.name } }

    assert_equal 1, listener.genre_exclusions.count
  end

  test "an off-site return_to is ignored" do
    sign_in_as user

    post genre_exclusions_path, params: { name: @hated.name, return_to: "//evil.test/" }

    assert_redirected_to root_path
  end

  test "an unknown genre is not found" do
    sign_in_as user

    post genre_exclusions_path, params: { name: "Nosuchgenre" }

    assert_response :not_found
  end

  test "the feed leaves out excluded events and says how many, linking to the settings" do
    listener = sign_in_as user(locale: "en")
    listener.genre_exclusions.create!(genre: @hated)

    get events_path

    assert_includes response.body, "CleanMarkerShow"
    refute_includes response.body, "MixedMarkerShow"
    assert_select ".day-summary__count--excluded[href=?][aria-label=?]",
                  settings_path(anchor: "excluded-genres"), "1 event left out because of your exclusions.",
                  text: "1"
  end

  test "when every matching event is excluded, the empty feed says why" do
    listener = sign_in_as user(locale: "en")
    listener.genre_exclusions.create!(genre: @liked)

    get events_path

    assert_select ".day-summary__count--excluded", false
    assert_select ".events-excluded a[href=?]", settings_path(anchor: "excluded-genres"),
                  text: "2 events left out because of your exclusions."
  end

  test "the note counts only the day on screen" do
    listener = sign_in_as user(locale: "en")
    listener.genre_exclusions.create!(genre: @hated)
    later = Date.new(2030, 1, 5)
    2.times { event_with_genres(@hated.name).update!(start_date: later) }
    event_with_genres(@liked.name).update!(start_date: later)

    get events_path

    assert_select ".day-summary__count--excluded", text: "1"
  end

  test "a day whose events are all excluded is skipped" do
    listener = sign_in_as user
    listener.genre_exclusions.create!(genre: @hated)
    only_excluded = Date.new(2030, 1, 2)
    next_day = Date.new(2030, 1, 3)
    event_with_genres(@hated.name).update!(start_date: only_excluded)
    event_with_genres(@liked.name).update!(start_date: next_day)

    get events_path(day: only_excluded.iso8601)

    assert_redirected_to events_path(day: next_day.iso8601)
  end

  test "filtering for an excluded genre shows its events and no note" do
    listener = sign_in_as user
    listener.genre_exclusions.create!(genre: @hated)

    get events_path(g: [@hated.name])

    assert_includes response.body, "MixedMarkerShow"
    assert_select ".day-summary__count--excluded", false
  end

  test "the what sheet counts leave out excluded events" do
    root = genre(name: "Exroot")
    @hated.set_parent!(root)
    @liked.set_parent!(root)
    listener = sign_in_as user
    listener.genre_exclusions.create!(genre: @hated)

    get filter_options_tags_path(field: "what")

    assert_select ".opt[data-search='#{@liked.name}'] .opt__count", text: "1"
    assert_select ".opt[data-search='#{@hated.name}'] .opt__count", text: "1"
  end

  test "saved events are not affected" do
    listener = sign_in_as user
    listener.genre_exclusions.create!(genre: @hated)
    listener.event_saves.create!(event: @mixed)

    get saved_events_path

    assert_includes response.body, "MixedMarkerShow"
  end

  test "the settings list excluded genres, and removing one lifts it with its aliases" do
    listener = sign_in_as user
    variant = genre(name: "Exoldname")
    listener.genre_exclusions.create!(genre: variant)
    listener.genre_exclusions.create!(genre: @hated)
    variant.merge_into!(@hated)

    get settings_path

    assert_select "#excluded-genres form[action=?]", genre_exclusion_path(@hated), count: 1

    delete genre_exclusion_path(@hated)

    assert_redirected_to settings_path(anchor: "excluded-genres")
    assert_empty listener.genre_exclusions.reload
  end

  test "the settings say so when nothing is excluded" do
    sign_in_as user

    get settings_path

    assert_select "#excluded-genres form", false
    assert_select "#excluded-genres p.muted", count: 2
  end

  private

  def dom_id(record) = ActionView::RecordIdentifier.dom_id(record)
end
