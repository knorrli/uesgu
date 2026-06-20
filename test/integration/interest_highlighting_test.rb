require 'db_test_helper'

# Locks the events-list interest highlighting end to end: a saved filter lights
# matching rows (amber rule + flag) and leaves the rest alone. Synthetic taxonomy
# only (see db_test_helper).
class InterestHighlightingTest < ActionDispatch::IntegrationTest
  def save_filter(owner, **filter)
    owner.saved_filters.create!(cadence: 'daily', time_of_day: 18 * 60, weekday: 1, monthday: 1,
                                notify_in_app: false, notify_push: false, notify_email: false,
                                filter_attributes: filter)
  end

  test 'a saved filter highlights matching shows and flags the matched genre' do
    u = sign_in_as user
    parent = genre(name: 'rock')
    child  = genre(name: 'shoegaze', parent: parent)
    save_filter(u, g: [parent.name])

    match = event(start_date: Date.current + 3, title: 'Interesting Show', genre_list: [child.name])
    other = event(start_date: Date.current + 3, title: 'Plain Show', genre_list: [genre(name: 'techno').name])

    get events_path
    assert_response :success
    assert_select "##{dom_id(match)}.is-interest", 1, 'matching row carries the interest rule'
    assert_select "##{dom_id(other)}.is-interest", 0, 'unmatched row stays plain'
    assert_select "##{dom_id(match)} .interest-flag .ph-flag", 1, 'the matched genre is flagged'
  end

  test 'no saved filters → no interest markers' do
    sign_in_as user
    event(start_date: Date.current + 3, genre_list: [genre(name: 'rock').name])

    get events_path
    assert_response :success
    assert_select '.is-interest', 0
    assert_select '.interest-flag', 0
  end
end
