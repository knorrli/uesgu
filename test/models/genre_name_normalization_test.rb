require "db_test_helper"

class GenreNameNormalizationTest < ActiveSupport::TestCase
  test "display strips a trailing dot the prose miner leaves behind" do
    assert_equal "Flarnwave", Genre.display_name_for("Flarnwave.")
  end

  test "display strips surrounding prose punctuation, keeping accented edge letters" do
    assert_equal "Flärnbass", Genre.display_name_for("…Flärnbass!")
    assert_equal "Éthérwave", Genre.display_name_for("(Éthérwave)")
  end

  test "display leaves interior separators alone" do
    assert_equal "Flarn-Punk", Genre.display_name_for("flarn-punk")
    assert_equal "Flarn & Wave", Genre.display_name_for("flarn & wave")
  end

  test "stripping edge punctuation does not change the fingerprint (still matches)" do
    assert_equal Genre.fingerprint_for("Flarnwave"), Genre.fingerprint_for("Flarnwave.")
  end

  test "minting a dotted token creates a clean row and reuses it for the clean spelling" do
    before = Genre.count
    Genre.ensure!(["Flarndrone."])
    row = Genre.find_by(fingerprint: Genre.fingerprint_for("Flarndrone"))
    assert_equal "Flarndrone", row.name
    assert_equal before + 1, Genre.count

    Genre.ensure!(["Flarndrone"])
    assert_equal before + 1, Genre.count
  end

  test "an all-punctuation token mints nothing" do
    before = Genre.count
    Genre.ensure!(["...", "…", "!!"])
    assert_equal before, Genre.count
  end

  test "genre_list= stores the cleaned tag and drops all-noise tokens" do
    e = event(genre_list: ["Improvisierte Flarnforschung.", "..."])
    assert_equal ["Improvisierte Flarnforschung"], e.reload.genre_list
  end

  test "a dotted token resolves onto an existing clean genre row" do
    genre(name: "Flarnstep")
    e = event(genre_list: ["Flarnstep."])
    assert_equal ["Flarnstep"], e.reload.genre_list
  end

  def saved_filter(owner, genres)
    rule = owner.saved_filters.new(cadence: "daily", time_of_day: 18 * 60)
    rule.filter_attributes = { g: genres }
    rule.save!
    rule
  end

  test "a rename rewrites the tag on every event carrying the old spelling" do
    flarndj = Genre.create!(name: "Flarndj")
    show = event_with_genres("flarn-dj")

    assert flarndj.rename!("FlarnDJ")

    assert_equal ["FlarnDJ"], show.reload.genre_list
    assert_equal "FlarnDJ", flarndj.reload.name
  end

  test "a rename repoints the saved filters holding the old spelling" do
    flarndj = Genre.create!(name: "Flarndj")
    watcher = saved_filter(user, ["Flarndj"])

    flarndj.rename!("FlarnDJ")

    assert_equal ["FlarnDJ"], watcher.reload.genres
  end

  test "a rename onto a spelling another genre already answers to is refused" do
    Genre.create!(name: "Flarnstep")
    flarndrone = Genre.create!(name: "Flarndrone")

    refute flarndrone.rename!("flarn-step")

    assert_equal "Flarndrone", flarndrone.name
    assert_equal "Flarndrone", flarndrone.reload.name
  end

  test "a rename to nothing at all is refused" do
    flarndrone = Genre.create!(name: "Flarndrone")

    refute flarndrone.rename!("   ")

    assert_equal "Flarndrone", flarndrone.reload.name
  end
end
