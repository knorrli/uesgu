require "db_test_helper"

# The rule that decides whether a slash in a captured genre is a list or part of a
# name. Synthetic genre names throughout; only the last test reads the table.
class EventCapture::GenresTest < ActiveSupport::TestCase
  def taxonomy(*names) = EventCapture::Genres.new(names)

  test "a run whose parts the taxonomy knows is a list" do
    assert_equal %w[Zorpcore Flarnwave],
                 taxonomy("Zorpcore", "Flarnwave").split("Zorpcore/Flarnwave")
  end

  # The motivating poster: six genres in one string, half of them names nobody
  # carries yet. One vouched part is what says the slash is a separator.
  test "one known part carries the parts nobody knows with it" do
    assert_equal %w[Loops Zorpcore FX Flarnwave],
                 taxonomy("Zorpcore").split("Loops/Zorpcore/FX/Flarnwave")
  end

  test "a run vouched for by nothing stays one genre" do
    assert_equal ["Loops/FX"], taxonomy("Zorpcore").split("Loops/FX")
  end

  test "a name the taxonomy carries with a slash in it is never split" do
    assert_equal ["Zorp/Flarn"], taxonomy("Zorp/Flarn", "Zorp").split("Zorp/Flarn")
  end

  # The fingerprint discards the slash and reads "&" as "and", so the stored spelling
  # and the poster's are only the same key once the run is rejoined with the ampersand.
  test "a slash standing in for the ampersand of a stored name is not a separator" do
    assert_equal ["Zorp/Flarn"], taxonomy("Zorp & Flarn", "Zorp", "Flarn").split("Zorp/Flarn")
  end

  test "a genre with no slash in it comes back untouched" do
    assert_equal ["Zorpcore"], taxonomy("Zorpcore").split("Zorpcore")
  end

  test "surrounding space and empty parts are not genres" do
    assert_equal %w[Zorpcore Flarnwave],
                 taxonomy("Zorpcore").split(" Zorpcore / Flarnwave /")
  end

  test "with nothing to vouch for anything, every run stays whole" do
    assert_equal ["Zorpcore/Flarnwave"], EventCapture::Genres.none.split("Zorpcore/Flarnwave")
  end

  # Blocked genres are scraper noise, so recognising one says nothing about the run.
  test "the taxonomy it reads is every genre that is not blocked" do
    carried = genre(name: "zorpcore")
    blocked = genre(name: "flarnwave")
    blocked.block!

    known = EventCapture::Genres.known

    assert_equal ["#{blocked.name}/loops"], known.split("#{blocked.name}/loops")
    assert_equal [carried.name, "loops"], known.split("#{carried.name}/loops")
  end
end
