require "db_test_helper"

class EventCapture::GenresTest < ActiveSupport::TestCase
  SEPARATORS = %w[/ · |].freeze

  def taxonomy(*names) = EventCapture::Genres.for_names(names)

  test "a run whose parts the taxonomy knows is a list, whatever separates them" do
    SEPARATORS.each do |separator|
      assert_equal %w[Zorpcore Flarnwave],
                   taxonomy("Zorpcore", "Flarnwave").split("Zorpcore#{separator}Flarnwave"),
                   "separator #{separator.inspect}"
    end
  end

  test "a name the taxonomy carries stays whole whatever separates its words" do
    SEPARATORS.each do |separator|
      run = "Zorp#{separator}Flarn"

      assert_equal [run], taxonomy("Zorp & Flarn", "Zorp", "Flarn").split(run),
                   "separator #{separator.inspect}"
    end
  end

  test "separators mix inside a single run" do
    assert_equal %w[Loops Zorpcore FX],
                 taxonomy("Zorpcore").split("Loops/Zorpcore·FX")
  end

  test "a hyphen never separates" do
    assert_equal ["Zorpcore-Flarnwave"], taxonomy("Zorpcore").split("Zorpcore-Flarnwave")
  end

  test "one known part carries the parts nobody knows with it" do
    assert_equal %w[Loops Zorpcore FX Flarnwave],
                 taxonomy("Zorpcore").split("Loops/Zorpcore/FX/Flarnwave")
  end

  test "a run vouched for by nothing stays one genre" do
    assert_equal ["Loops/FX"], taxonomy("Zorpcore").split("Loops/FX")
  end

  test "a name the taxonomy carries with a separator in it is never split" do
    assert_equal ["Zorp/Flarn"], taxonomy("Zorp/Flarn", "Zorp").split("Zorp/Flarn")
  end

  test "a genre with no separator in it comes back untouched" do
    assert_equal ["Zorpcore"], taxonomy("Zorpcore").split("Zorpcore")
  end

  test "surrounding space and empty parts are not genres" do
    assert_equal %w[Zorpcore Flarnwave],
                 taxonomy("Zorpcore").split(" Zorpcore / Flarnwave /")
  end

  test "with nothing to vouch for anything, every run stays whole" do
    assert_equal ["Zorpcore/Flarnwave"], EventCapture::Genres.none.split("Zorpcore/Flarnwave")
  end

  test "the taxonomy it reads is every genre that is not blocked" do
    carried = genre(name: "zorpcore")
    blocked = genre(name: "flarnwave")
    blocked.block!

    known = EventCapture::Genres.known

    assert_equal ["#{blocked.name}/loops"], known.split("#{blocked.name}/loops")
    assert_equal [carried.name, "loops"], known.split("#{carried.name}/loops")
  end
end
