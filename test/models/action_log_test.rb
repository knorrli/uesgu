require "db_test_helper"

class ActionLogTest < ActiveSupport::TestCase
  setup { @moderator = user(username: "zorpmod") }

  def dismiss(event, by: @moderator) = ActionLog.track("event.dismiss", event, user: by) { event.dismiss! }

  test "an action records who did it, to what, and only the attributes it changed" do
    show = event(title: "Zorp Night")

    entry = dismiss(show)

    assert_equal @moderator, entry.user
    assert_equal "events", entry.area
    assert_equal show, entry.subject
    assert_equal "Zorp Night", entry.subject_label
    assert_equal ["dismissed_at"], entry.before.keys
  end

  test "an action that changes nothing is not logged" do
    show = event
    show.dismiss!

    assert_no_difference -> { ActionLog.count } do
      dismiss(show)
    end
  end

  test "undoing a removal brings the event back and logs the undo against the original" do
    show = event
    entry = dismiss(show)

    undo = entry.undo!(user: user(username: "zorpadmin"))

    refute_predicate show.reload, :dismissed?
    assert_predicate undo, :undo?
    assert_equal entry, undo.reverts
    assert_equal "events", undo.area
  end

  test "an undone action cannot be undone again, and an undo cannot be undone" do
    entry = dismiss(event)
    undo = entry.undo!(user: @moderator)

    refute_predicate entry.reload, :undoable?
    refute_predicate undo, :undoable?
    assert_raises(ArgumentError) { entry.undo!(user: @moderator) }
  end

  test "an action is no longer undoable once a later action touched the same event" do
    show = event
    first = dismiss(show)
    later = ActionLog.track("event.restore", show, user: user(username: "zorpother")) { show.undismiss! }

    refute_predicate first, :undoable?
    assert_equal later, first.superseded_by
    assert_predicate later, :undoable?
  end

  test "undoing a merge restores the standalone event and its unlocked link" do
    canonical = event(title: "Zorp Night")
    duplicate = event(title: "Zorp Night (copy)")
    entry = ActionLog.track("event.merge", duplicate, user: @moderator) { duplicate.merge_into!(canonical) }

    entry.undo!(user: @moderator)

    duplicate.reload
    assert_nil duplicate.canonical_event_id
    refute duplicate.overridden?(:canonical_event)
  end

  test "undoing an edit restores the old values and the old genres, but not fields it never touched" do
    show = event(title: "Wrong Title", description: "Scraped", genre_list: ["zorpwave"])
    original_genres = show.reload.genre_list.to_a
    before = show.undo_snapshot
    show.update!(title: "Right Title", genre_list: ["zorpcore"], overridden_fields: %w[title genres])
    entry = ActionLog.record!("event.edit", show, before: before, user: @moderator)
    show.update!(description: "Rescraped")

    entry.undo!(user: @moderator)

    show.reload
    assert_equal "Wrong Title", show.title
    assert_equal original_genres, show.genre_list.to_a
    assert_empty show.overridden_fields
    assert_equal "Rescraped", show.description
  end

  test "an action on a deleted event stays in the log, without an undo" do
    show = event
    entry = dismiss(show)
    show.destroy!

    assert_nil entry.reload.subject
    assert_equal show.title, entry.subject_label
    refute_predicate entry, :undoable?
  end
end
