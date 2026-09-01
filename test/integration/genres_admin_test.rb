require "db_test_helper"

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

  test "an admin fixes a genre's spelling, and the events follow" do
    flarndj = Genre.create!(name: "Flarndj")
    show = event_with_genres("Flarndj")

    post rename_genre_path(flarndj), params: { genre: { name: "FlarnDJ" }, return_to: genres_path }

    assert_redirected_to genres_path
    assert_equal "FlarnDJ", flarndj.reload.name
    assert_equal ["FlarnDJ"], show.reload.genre_list
  end

  test "renaming a genre onto one that already exists is refused and says so" do
    Genre.create!(name: "Flarnstep")
    flarndrone = Genre.create!(name: "Flarndrone")

    post rename_genre_path(flarndrone), params: { genre: { name: "Flarn-Step" }, return_to: genres_path }

    assert_redirected_to genres_path
    assert_equal "Flarndrone", flarndrone.reload.name
    assert flash[:alert].present?
  end

  test "a merged genre is not offered a rename, the genre it resolves to is" do
    canonical = genre(events_count: 1)
    variant = genre(events_count: 1)
    variant.merge_into!(canonical)

    get edit_genre_path(variant)
    assert_select "form[action=?]", rename_genre_path(variant), count: 0

    get edit_genre_path(canonical)
    assert_select "form[action=?]", rename_genre_path(canonical)
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
    Genre.create!(name: "Flarn", events_count: 1)
    compound = Genre.create!(name: "Flarnwave", events_count: 99)

    get queue_genres_path

    assert_response :success
    assert_select ".genre-related" do
      assert_select "h3", text: I18n.t("genres.editor.related")
      assert_select ".genre-related__label", text: /Flarn/
      assert_select "form[action=?]", set_parent_genre_path(compound)
      assert_select "form[action=?]", merge_genre_path(compound)
    end
  end

  test "the set-parent picker renders the tree indented, umbrellas first" do
    root  = genre(name: "flarnroot", events_count: 5)
    child = genre(name: "flarnchild", events_count: 2, parent: root)
    subject = genre(name: "flarnsubject", events_count: 9)

    get edit_genre_path(subject)

    assert_response :success
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

  test "filtering keeps the active sort and sorting keeps the active filter" do
    genre(events_count: 1)

    get genres_path(sort: "count")
    assert_select "a.tag[href=?]", genres_path(status: "unplaced", sort: "count")

    get genres_path(status: "unplaced")
    assert_select ".catalogue-sort-option[href=?]", genres_path(status: "unplaced", sort: "count")
  end

  test "an unknown status or sort falls back to the defaults" do
    genre(events_count: 1)

    get genres_path(status: "bogus", sort: "bogus")
    assert_response :success
    assert_select "a.tag.active[href=?]", genres_path(sort: "bogus")
    assert_select ".catalogue-sort-option.active[href=?]", genres_path(status: "bogus", sort: "name")
  end

  test "return_to honors an internal path" do
    g = genre(events_count: 1)
    post ignore_genre_path(g), params: { return_to: queue_genres_path }
    assert_redirected_to queue_genres_path
  end
end
