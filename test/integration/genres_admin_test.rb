require "db_test_helper"

# Locks the admin genre-curation flow through the controller: the set_parent
# (tree-filing) write path, each disposition endpoint, the queue that serves the
# next highest-impact unplaced genre, and the internal-only return_to. Disposition
# *behaviour* is unit-tested in genre_disposition_test; here we prove the
# endpoints wire through and redirect. Synthetic taxonomy only.
class GenresAdminTest < ActionDispatch::IntegrationTest
  setup { sign_in_as user(admin: true) }

  test "ignore, hide, block and restore each flip the genre state" do
    g = genre(events_count: 1)

    post ignore_genre_path(g)
    assert g.reload.ignored?

    post hide_genre_path(g)
    assert g.reload.hidden?

    post block_genre_path(g)
    assert g.reload.blocked?

    post restore_genre_path(g)
    refute g.reload.blocked?
    refute g.reload.hidden?
    refute g.reload.ignored?
  end

  test "set_parent files the genre under the chosen parent" do
    g = genre(events_count: 2)
    parent = genre

    post set_parent_genre_path(g), params: { genre: { parent_genre_id: parent.id }, return_to: genres_path }

    assert_redirected_to genres_path
    assert_equal parent.id, g.reload.parent_id
  end

  test "set_parent rejects a cycle and keeps the tree unchanged" do
    parent = genre
    g = genre; g.set_parent!(parent)

    post set_parent_genre_path(parent), params: { genre: { parent_genre_id: g.id } }

    assert_equal parent.id, g.reload.parent_id, "g still sits under parent"
    assert_nil parent.reload.parent_id, "the rejected re-parent left parent a root"
  end

  test "queue serves the highest-impact unplaced genre" do
    genre(name: "light", events_count: 2)
    heavy = genre(name: "heavy", events_count: 99)

    get queue_genres_path

    assert_response :success
    assert_includes response.body, heavy.name, "the most-used unplaced genre surfaces first"
  end

  test "tree renders the placed hierarchy for an admin" do
    rock = genre(name: "treerock", events_count: 3)
    punk = genre(name: "treepunk", events_count: 2); punk.set_parent!(rock)
    genre(name: "treehidden", events_count: 1).hide!

    get tree_genres_path

    assert_response :success
    assert_includes response.body, rock.name
    assert_includes response.body, punk.name
    refute_includes response.body, "treehidden", "disposed genres sit outside the tree"
  end

  test "queue editor surfaces related genres with file + merge actions" do
    # Exact names (not the suffixing `genre` helper) so 'flarn' really is a
    # substring of 'flarnwave' — the relationship the suggester keys on.
    Genre.create!(name: "Flarn", events_count: 1)                 # an existing stem
    compound = Genre.create!(name: "Flarnwave", events_count: 99) # the queue head

    get queue_genres_path

    assert_response :success
    assert_select ".genre-related" do
      assert_select "h3", text: I18n.t("genres.editor.related")
      assert_select ".genre-related__label", text: /Flarn/
      assert_select "form[action=?]", set_parent_genre_path(compound) # file under it
      assert_select "form[action=?]", merge_genre_path(compound)      # or merge into it
    end
  end

  test "the set-parent picker renders the tree indented, umbrellas first" do
    root  = genre(name: "flarnroot", events_count: 5)
    child = genre(name: "flarnchild", events_count: 2, parent: root)
    subject = genre(name: "flarnsubject", events_count: 9)

    get edit_genre_path(subject)

    assert_response :success
    # The root sits at depth 0 (flush) and its sub-genre one level in — the tree
    # is visible in the dropdown, not a flat alphabetical wall.
    assert_select ".genre-set-parent .genre-tree-option[data-depth=0] .genre-option-name.umbrella",
                  text: root.name
    assert_select ".genre-set-parent .genre-tree-option[data-depth=1] .genre-option-name",
                  text: child.name
  end

  test "index and edit render for an admin" do
    g = genre(events_count: 1)
    get genres_path
    assert_response :success
    get edit_genre_path(g)
    assert_response :success
  end

  test "return_to honors an internal path" do
    g = genre(events_count: 1)
    post ignore_genre_path(g), params: { return_to: queue_genres_path }
    assert_redirected_to queue_genres_path
  end
end
