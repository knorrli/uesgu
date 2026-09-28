require "db_test_helper"

class ExcludedGenresTest < ActiveSupport::TestCase
  setup do
    @listener = user
  end

  test "without a user nothing is excluded" do
    shown = event_with_genres(genre(name: "exnone").name)

    assert_equal [shown], ExcludedGenres.for(nil).apply(Event.where(id: shown.id)).to_a
    assert_empty ExcludedGenres.for(nil).excluded_from(Event.all)
  end

  test "an event is left out when any of its genres is excluded" do
    hated = genre(name: "exhated")
    liked = genre(name: "exliked")
    mixed = event_with_genres(hated.name, liked.name)
    clean = event_with_genres(liked.name)
    exclude(hated)

    assert_equal [clean], shown
    assert_equal [mixed], ExcludedGenres.for(@listener).excluded_from(Event.all).to_a
  end

  test "excluding a genre also excludes its subgenres" do
    parent = genre(name: "exparent")
    child = genre(name: "exchild", parent: parent)
    grandchild = genre(name: "exgrandchild", parent: child)
    event_with_genres(child.name)
    event_with_genres(grandchild.name)
    exclude(parent)

    assert_empty shown
  end

  test "an event tagged with a merged-away alias is left out with its canonical" do
    canonical = genre(name: "excanonical")
    variant = genre(name: "exvariant")
    event_with_genres(variant.name)
    variant.merge_into!(canonical)
    exclude(canonical)

    assert_empty shown
  end

  test "an exclusion follows its genre when it is merged into another" do
    merged = genre(name: "exmerged")
    survivor = genre(name: "exsurvivor")
    event_with_genres(survivor.name)
    exclude(merged)
    merged.merge_into!(survivor)

    assert_empty shown
  end

  test "an exclusion follows its genre through a rename" do
    renamed = genre(name: "exbefore")
    event_with_genres(renamed.name)
    exclude(renamed)
    renamed.rename!("exafter-#{TaxonomyFixtures.next_seq}")

    assert_empty shown
  end

  test "picking an excluded genre shows its events in that view" do
    hated = genre(name: "expicked")
    other = genre(name: "exother")
    alone = event_with_genres(hated.name)
    with_other = event_with_genres(hated.name, other.name)
    exclude(hated)

    assert_equal [alone, with_other].sort, shown(picked: [hated.name]).sort
  end

  test "picking a subgenre lifts the exclusion of its parent" do
    parent = genre(name: "exliftparent")
    child = genre(name: "exliftchild", parent: parent)
    both = event_with_genres(parent.name, child.name)
    exclude(parent)

    assert_equal [both], shown(picked: [child.name])
  end

  test "picking the parent of an excluded genre does not lift it" do
    parent = genre(name: "exkeepparent")
    child = genre(name: "exkeepchild", parent: parent)
    event_with_genres(parent.name, child.name)
    plain = event_with_genres(parent.name)
    exclude(child)

    assert_equal [plain], shown(picked: [parent.name])
  end

  test "picking one excluded genre leaves the other exclusions in place" do
    first = genre(name: "exfirst")
    second = genre(name: "exsecond")
    event_with_genres(first.name, second.name)
    only_first = event_with_genres(first.name)
    exclude(first)
    exclude(second)

    assert_equal [only_first], shown(picked: [first.name])
  end

  test "a genre count is what picking that genre returns, the excluded genre's own included" do
    root = genre(name: "excountroot")
    hated = genre(name: "excounthated", parent: root)
    liked = genre(name: "excountliked", parent: root)
    event_with_genres(hated.name)
    event_with_genres(hated.name, liked.name)
    event_with_genres(liked.name)
    exclude(hated)

    counts = ExcludedGenres.for(@listener).genre_filter_counts

    [root, hated, liked].each do |node|
      assert_equal shown(picked: [node.name], filtered: true).size, counts.fetch(node.id, 0), node.name
    end
    assert_equal [1, 2, 1], [root, hated, liked].map { |node| counts.fetch(node.id, 0) }
  end

  test "location counts leave out excluded events" do
    hated = genre(name: "exlochated")
    spot = place(name: "Exsaal", locality: "Exwil", canton: "GE")
    tags = [spot.name, spot.locality, spot.canton]
    event(location_list: tags).update!(genre_list: [hated.name])
    event(location_list: tags)
    exclude(hated)

    assert_equal 1, ExcludedGenres.for(@listener).location_filter_counts["GE"]
  end

  private

  def exclude(genre)
    @listener.genre_exclusions.create!(genre: genre)
  end

  def shown(picked: [], filtered: false)
    events = filtered ? Event.visible.ransack(Filter.build(genres: picked).ransack_query).result(distinct: true) : Event.all
    ExcludedGenres.for(@listener, picked: picked).apply(events).to_a
  end
end
