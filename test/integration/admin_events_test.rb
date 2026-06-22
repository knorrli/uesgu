require 'db_test_helper'

# Read-only events browser under /admin/events: admin-gated, with visibility
# filters, title search, and sort. The admin sees everything (the public index
# is scoped to :visible).
class AdminEventsTest < ActionDispatch::IntegrationTest
  test 'guests are sent to login, non-admins are forbidden' do
    get admin_events_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_events_path
    assert_response :forbidden
  end

  test 'an admin can browse, filter and search events' do
    event(title: 'Loud Guitars')
    event(title: 'Quiet Reading', hidden: true)
    event(title: 'Called Off', cancelled_at: Time.utc(2030, 1, 1))
    sign_in_as user(admin: true)

    get admin_events_path
    assert_response :success
    assert_select 'a', text: 'Loud Guitars'
    assert_select 'a', text: 'Quiet Reading'

    get admin_events_path(status: 'hidden')
    assert_select 'a', text: 'Quiet Reading'
    assert_select 'a', text: 'Loud Guitars', count: 0

    get admin_events_path(status: 'visible')
    assert_select 'a', text: 'Loud Guitars'
    assert_select 'a', text: 'Quiet Reading', count: 0

    get admin_events_path(status: 'cancelled')
    assert_select 'a', text: 'Called Off'
    assert_select 'a', text: 'Loud Guitars', count: 0

    get admin_events_path(q: 'loud')
    assert_select 'a', text: 'Loud Guitars'
    assert_select 'a', text: 'Called Off', count: 0
  end

  test 'the default date sort lists events chronologically (oldest first)' do
    later = event(title: 'LaterShow', start_date: Date.current + 30.days)
    sooner = event(title: 'SoonerShow', start_date: Date.current + 2.days)
    sign_in_as user(admin: true)

    get admin_events_path
    assert_response :success
    assert_operator @response.body.index('SoonerShow'), :<, @response.body.index('LaterShow')
  end

  test 'the show page renders the edit form and surfaces locked fields' do
    e = event(title: 'Editable Show')
    e.lock_field!(:title)
    sign_in_as user(admin: true)

    get admin_event_path(e)
    assert_response :success
    assert_select 'input[name=?]', 'event[title]'
    assert_select 'input[name=?]', 'event[date]'
    assert_select 'input[name=?]', 'event[time]'
    # The locked title appears in the "manual overrides" list with a revert form.
    assert_select 'form[action=?]', revert_admin_event_path(e, field: 'title')
  end

  test 'editing an event locks only the fields the admin changed' do
    e = event(title: 'Wrong Title', description: 'Keep Me')
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: 'Fixed Title', description: 'Keep Me',
      date: e.start_date.iso8601, time: '20:30'
    } }
    assert_redirected_to admin_event_path(e)

    e.reload
    assert_equal 'Fixed Title', e.title
    assert e.overridden?(:title)
    refute e.overridden?(:description) # resubmitted unchanged → not locked
    # The time went from none → 20:30, so the date/time pair locks together.
    assert e.overridden?(:start_time)
    assert e.overridden?(:start_date)
  end

  test 'update ignores params outside the editable set' do
    e = event(title: 'T')
    original_url = e.url
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: 'T', description: '', date: e.start_date.iso8601, time: '',
      url: 'https://evil.test/changed', hidden: true
    } }

    e.reload
    assert_equal original_url, e.url
    refute e.hidden?
    assert_empty e.overridden_fields # nothing editable actually changed
  end

  test 'reverting a locked field releases it back to the scraper' do
    e = event
    e.lock_field!(:title)
    sign_in_as user(admin: true)

    patch revert_admin_event_path(e, field: 'title')
    assert_redirected_to admin_event_path(e)
    refute e.reload.overridden?(:title)
  end

  test 'reverting the schedule releases both date and time' do
    e = event
    e.lock_field!(:start_date)
    e.lock_field!(:start_time)
    sign_in_as user(admin: true)

    patch revert_admin_event_path(e, field: 'start_date')

    e.reload
    refute e.overridden?(:start_date)
    refute e.overridden?(:start_time)
  end

  test 'editing genres pins the list and re-derives styles, revertible like a scalar' do
    e = event(title: 'Genre Show')
    g1 = genre(name: 'aaa')
    g2 = genre(name: 'bbb')
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: 'Genre Show', description: '', date: e.start_date.iso8601, time: '',
      override_genre_ids: "#{g1.id},#{g2.id}"
    } }
    assert_redirected_to admin_event_path(e)

    e.reload
    assert_equal [g1.name, g2.name].sort, e.genre_list.sort
    assert e.overridden?(:genres)

    # Pinned genres surface in the manual-overrides list with a revert form.
    get admin_event_path(e)
    assert_select 'form[action=?]', revert_admin_event_path(e, field: 'genres')

    patch revert_admin_event_path(e, field: 'genres')
    refute e.reload.overridden?(:genres)
  end

  test 'an admin can dismiss an event and restore it' do
    e = event(title: 'Bin Me')
    sign_in_as user(admin: true)

    delete admin_event_path(e)
    assert_redirected_to admin_events_path(status: 'dismissed')
    assert e.reload.dismissed?

    patch undismiss_admin_event_path(e)
    assert_redirected_to admin_event_path(e)
    refute e.reload.dismissed?
  end

  test 'guests and non-admins cannot dismiss events' do
    e = event(title: 'Safe')
    delete admin_event_path(e)
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    delete admin_event_path(e)
    assert_response :forbidden
    refute e.reload.dismissed?
  end

  test 'the events list pages with the shared prev/next readout' do
    51.times { |i| event(title: "Show #{format('%02d', i)}") }
    sign_in_as user(admin: true)

    # Page 1 of 2: a readout and a working "next" link, no "prev" link.
    get admin_events_path(sort: 'title')
    assert_response :success
    assert_select '.pagination__status', text: /1 .* 2/
    assert_select '.pagination a[rel=next][href*="page=2"]'
    assert_select '.pagination a[rel=prev]', count: 0
    # Filter params survive into the page links.
    assert_select '.pagination a[rel=next][href*="sort=title"]'

    # Page 2: a working "prev" link, no "next" link.
    get admin_events_path(sort: 'title', page: 2)
    assert_select '.pagination a[rel=prev][href*="page=1"]'
    assert_select '.pagination a[rel=next]', count: 0
  end

  test 'an admin can merge an event into a canonical and split it back out' do
    canonical = event(title: 'PETZI Version')
    dup = event(title: 'Venue Version')
    sign_in_as user(admin: true)

    patch merge_admin_event_path(dup), params: { canonical_id: canonical.id }
    assert_redirected_to admin_event_path(canonical)
    dup.reload
    assert_equal canonical.id, dup.canonical_event_id
    assert dup.overridden?(:canonical_event), 'merge is pinned against dedup'
    refute_includes Event.visible, dup

    patch unmerge_admin_event_path(dup)
    assert_redirected_to admin_event_path(dup)
    assert_nil dup.reload.canonical_event_id
    assert dup.overridden?(:canonical_event), 'standalone decision stays pinned'
    assert_includes Event.visible, dup
  end

  test 'merging an event into itself is rejected' do
    e = event(title: 'Solo')
    sign_in_as user(admin: true)

    patch merge_admin_event_path(e), params: { canonical_id: e.id }
    assert_redirected_to admin_event_path(e)
    assert_nil e.reload.canonical_event_id
  end

  test 'merging without picking a canonical is rejected gracefully' do
    e = event(title: 'Unpicked')
    sign_in_as user(admin: true)

    patch merge_admin_event_path(e), params: { canonical_id: '' }
    assert_redirected_to admin_event_path(e)
    assert_nil e.reload.canonical_event_id
  end

  test 'the merge picker searches canonical events by title, excluding self' do
    current = event(title: 'Editing This One')
    match = event(title: 'Matching Canonical')
    event(title: 'Unrelated')
    sign_in_as user(admin: true)

    # Request format as a URL param (format: :turbo_stream), exactly as the
    # combobox's async fetch does — not `as: :turbo_stream` (an Accept header),
    # which leaves :html in the format list and lets the option partial resolve
    # via fallback, masking the missing-template 500 the real request hits.
    get search_admin_events_path(exclude: current.id, q: 'Matching', format: :turbo_stream)
    assert_response :success
    assert_match 'Matching Canonical', response.body
    assert_no_match 'Unrelated', response.body
    assert_no_match 'Editing This One', response.body
  end

  test 'the show page surfaces the merge form and the duplicate relationship' do
    canonical = event(title: 'The Canonical')
    dup = event(title: 'The Duplicate')
    dup.merge_into!(canonical)
    sign_in_as user(admin: true)

    # canonical lists its merged duplicates
    get admin_event_path(canonical)
    assert_select 'a', text: 'The Duplicate'
    assert_select 'form[action=?]', merge_admin_event_path(canonical)

    # the duplicate offers an unmerge action
    get admin_event_path(dup)
    assert_select 'form[action=?]', unmerge_admin_event_path(dup)
  end

  test 'guests and non-admins cannot merge events' do
    canonical = event(title: 'C')
    dup = event(title: 'D')
    patch merge_admin_event_path(dup), params: { canonical_id: canonical.id }
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    patch merge_admin_event_path(dup), params: { canonical_id: canonical.id }
    assert_response :forbidden
    assert_nil dup.reload.canonical_event_id
  end

  test 'guests and non-admins cannot edit events' do
    e = event(title: 'Untouched')
    patch admin_event_path(e), params: { event: { title: 'Hacked', date: e.start_date.iso8601 } }
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    patch admin_event_path(e), params: { event: { title: 'Hacked', date: e.start_date.iso8601 } }
    assert_response :forbidden
    assert_equal 'Untouched', e.reload.title
  end
end
