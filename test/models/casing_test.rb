require "test_helper"

class CasingTest < ActiveSupport::TestCase
  test "a string shouted as a whole is title-cased" do
    assert_equal "Michael Schenker Group", Casing.recase("MICHAEL SCHENKER GROUP")
  end

  test "a string carrying any lowercase is left alone" do
    assert_equal "LEYA + Junge Eko", Casing.recase("LEYA + Junge Eko")
    assert_equal "SENTO \"The Phoenix Tour\"", Casing.recase("SENTO \"The Phoenix Tour\"")
  end

  test "a lone shouted word is left alone" do
    ["KMFDM", "ECHT!", "EBBB", "R&B"].each do |name|
      assert_equal name, Casing.recase(name)
    end
  end

  # Single letters do not count towards the word tally, or the parenthesised half of
  # this name would make it two and recase it.
  test "letters standing alone do not make a second word" do
    assert_equal "SUNN O)))", Casing.recase("SUNN O)))")
  end

  test "a parenthesised country code keeps its capitals" do
    assert_equal "Mitsune (JP/DE)", Casing.recase("MITSUNE (JP/DE)")
    assert_equal "Hatebreed (US) + Torba (IT)", Casing.recase("HATEBREED (US) + TORBA (IT)")
  end

  test "a parenthesised phrase is title-cased like the rest" do
    assert_equal "Slope (Same Kids)", Casing.recase("SLOPE (SAME KIDS)")
  end

  test "a letter run behind a digit is a suffix, not a word" do
    assert_equal "Best Of 2000er Party", Casing.recase("BEST OF 2000ER PARTY")
    assert_equal "Strictly 90ies", Casing.recase("STRICTLY 90IES")
  end

  test "what follows an apostrophe stays lowercase" do
    assert_equal "Otto's Garden", Casing.recase("OTTO'S GARDEN")
    assert_equal "Ain't Ur Enn", Casing.recase("AIN'T UR ENN")
  end

  test "accented capitals fold to their own lowercase" do
    assert_equal "Überland Festival", Casing.recase("ÜBERLAND FESTIVAL")
    assert_equal "Angélique Kidjo", Casing.recase("ANGÉLIQUE KIDJO")
  end

  test "separators survive the pass" do
    assert_equal "Post-Punk & Wave Night", Casing.recase("POST-PUNK & WAVE NIGHT")
  end

  test "a string with no letters at all is not shouted" do
    assert_not Casing.shouted?("2026")
    assert_equal "2026", Casing.recase("2026")
  end

  test "blank and nil pass through" do
    assert_nil Casing.recase(nil)
    assert_equal "", Casing.recase("")
  end
  test "an abbreviation of the domain keeps its conventional spelling" do
    assert_equal "DJ Patife (BR)", Casing.recase("DJ PATIFE (BR)")
    assert_equal "DJs All Night Long", Casing.recase("DJS ALL NIGHT LONG")
    assert_equal "MC Solaar", Casing.recase("MC SOLAAR")
    assert_equal "USA – Australien", Casing.recase("USA – AUSTRALIEN")
  end

  # Whole tokens only — the abbreviation must not reach inside a longer word.
  test "a word that merely starts with an abbreviation is title-cased" do
    assert_equal "Django Reinhardt", Casing.recase("DJANGO REINHARDT")
    assert_equal "Epilog Und Lparty", Casing.recase("EPILOG UND LPARTY")
  end

  # "us" is a pronoun far more often than it is a country, and the parenthesised form
  # is kept by the country-code rule instead.
  test "a country code that doubles as an ordinary word is not spared" do
    assert_equal "The Best Of Us", Casing.recase("THE BEST OF US")
    assert_equal "Alela Diane (US)", Casing.recase("ALELA DIANE (US)")
  end
end
