require "db_test_helper"

# The display-name normalization that runs when a scraped/prose-mined token is
# minted into taxonomy. The match key (fingerprint) is deliberately punctuation-
# blind, so the job here is purely cosmetic: strip the sentence punctuation a
# prose miner welds onto a token ("Virtuos." → "Virtuos") WITHOUT changing which
# genre it resolves to. Synthetic genre names only (never real taxonomy content).
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

    # The clean spelling shares the fingerprint, so it folds into the same row.
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
    genre(name: "Flarnstep") # pre-existing clean taxonomy
    e = event(genre_list: ["Flarnstep."])
    assert_equal ["Flarnstep"], e.reload.genre_list
  end
end
