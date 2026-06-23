require "db_test_helper"

# Locks the genre-tree mechanics on Genre: parent/child wiring, subtree
# expansion (the set a "filter by this genre" matches), set_parent! placement
# and its cycle guard, the unplaced curation scope, and the invariant that a
# disposition/alias detaches a genre from the tree. Pure mechanics — invented
# genre names only, never real taxonomy content (which the redesign churns).
class GenreTreeTest < ActiveSupport::TestCase
  test "subtree_ids returns the genre and all transitive descendants" do
    rock = genre(name: "flux-rock")
    punk = genre(name: "flux-punk");  punk.set_parent!(rock)
    crust = genre(name: "flux-crust"); crust.set_parent!(punk)
    other = genre(name: "flux-other")

    assert_equal [rock.id, punk.id, crust.id].sort, Genre.subtree_ids([rock.id]).sort
    refute_includes Genre.subtree_ids([rock.id]), other.id
  end

  test "subtree_ids is empty for no roots and handles multiple roots" do
    assert_empty Genre.subtree_ids([])
    a = genre(name: "flux-a"); a_child = genre(name: "flux-a-child"); a_child.set_parent!(a)
    b = genre(name: "flux-b")
    assert_equal [a.id, a_child.id, b.id].sort, Genre.subtree_ids([a.id, b.id]).sort
  end

  test "descendant_ids excludes self" do
    parent = genre(name: "flux-parent")
    child = genre(name: "flux-child"); child.set_parent!(parent)

    assert_equal [child.id], parent.descendant_ids
    assert_empty child.descendant_ids
  end

  test "set_parent! files the genre and clears any prior disposition" do
    g = genre(name: "flux-g", events_count: 3)
    g.hide!
    parent = genre(name: "flux-roots")

    g.set_parent!(parent)

    assert_equal parent.id, g.reload.parent_id
    assert g.placed?
    refute g.hidden?
  end

  test "set_parent! accepts a bare id and a blank value makes it a root" do
    parent = genre(name: "flux-p")
    g = genre(name: "flux-leaf")

    g.set_parent!(parent.id)
    assert_equal parent.id, g.reload.parent_id

    g.set_parent!("")
    assert_nil g.reload.parent_id
    refute g.placed?
  end

  test "set_parent! rejects parenting a genre under itself or a descendant" do
    rock = genre(name: "flux-rock2")
    punk = genre(name: "flux-punk2"); punk.set_parent!(rock)

    assert_raises(ArgumentError) { rock.set_parent!(rock) }
    assert_raises(ArgumentError) { rock.set_parent!(punk) } # punk is rock's descendant
    assert_nil rock.reload.parent_id, "a rejected re-parent leaves the tree unchanged"
  end

  test "unplaced is in-use leaf genres with no parent and no disposition" do
    root = genre(name: "flux-root", events_count: 5)
    placed = genre(name: "flux-placed", events_count: 5); placed.set_parent!(root)
    waiting = genre(name: "flux-waiting", events_count: 5)
    unused = genre(name: "flux-unused", events_count: 0)
    hidden = genre(name: "flux-hidden", events_count: 5); hidden.hide!

    ids = Genre.unplaced.pluck(:id)
    assert_includes ids, waiting.id
    refute_includes ids, placed.id, "a placed genre has left the queue"
    refute_includes ids, root.id, "a root (has children, no parent) is not unplaced"
    refute_includes ids, unused.id, "a genre on no events is not queued"
    refute_includes ids, hidden.id, "a disposed genre is not queued"
  end

  test "dispositions and merge detach a genre from the tree" do
    parent = genre(name: "flux-bigtop")
    %i[hide! ignore! block!].each do |op|
      child = genre(name: "flux-x-#{op}", events_count: 1); child.set_parent!(parent)
      child.public_send(op)
      assert_nil child.reload.parent_id, "#{op} should detach from the tree"
    end

    merged = genre(name: "flux-merge", events_count: 1); merged.set_parent!(parent)
    merged.merge_into!(genre(name: "flux-canon"))
    assert_nil merged.reload.parent_id, "merge should detach from the tree"
  end

  test "restore returns a placed genre to the unplaced queue" do
    parent = genre(name: "flux-root3")
    g = genre(name: "flux-restore", events_count: 2); g.set_parent!(parent)

    g.restore!

    assert_nil g.reload.parent_id
    assert_includes Genre.unplaced.pluck(:id), g.id
  end
end
