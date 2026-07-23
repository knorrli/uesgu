require "test_helper"

# Locks the Sedel genre splitter independent of the big captured fixture.
#
# Sedel's style field is a Drupal entity reference, but the venue mints terms
# that are themselves COMBINED genre strings, with two different separators in
# the wild (spaced or not):
#
#   * "Crustpunk Hardcore / Speed Metal D-Beat Punk"  — slash
#   * "Darkmetal | Blackmetal"                        — pipe
#   * "Punkrock/Folk"                                 — slash, no spaces
#
# The old code split the wrapper's text on the literal " | " only, so a
# slash-joined term shipped as one giant genre token. The splitter now works
# per field-item and splits on both separators — but NEVER on whitespace:
# multi-word genres ("Speed Metal", "Punk Rock") are legitimate single tokens,
# and hyphenated names ("D-Punk", "Garage-Punk-n-Roll") must stay intact.
# SYNTHETIC genre strings shaped like the live ones — no real taxonomy content.
class Scrapers::SedelTest < Minitest::Test
  # raw stil-taxo term => expected genre tokens
  CASES = {
    "Punk Rock"                                     => ["Punk Rock"], # multi-word stays whole
    "Fast Palm-Muted Chugcore / Post-Hardcore"      => ["Fast Palm-Muted Chugcore", "Post-Hardcore"],
    "Darkgaze | Blackwave"                          => ["Darkgaze", "Blackwave"],
    "Folkpunk/Polka"                                => ["Folkpunk", "Polka"], # unspaced slash
    "Garage-Punk-n-Roll"                            => ["Garage-Punk-n-Roll"], # hyphens intact
    "EBM / New Beat"                                => ["EBM", "New Beat"],
    ""                                              => []
  }.freeze

  def test_splits_combined_genre_terms_on_slash_and_pipe
    CASES.each do |raw, expected|
      assert_equal expected, genres_for([raw]), "term #{raw.inspect}"
    end
  end

  # A proper multi-value field (several field-items) still yields one token per
  # item, composing with the in-item separator split.
  def test_multiple_field_items_each_split
    assert_equal ["Speed Polka", "D-Beat", "Schunkelcore"],
                 genres_for(["Speed Polka / D-Beat", "Schunkelcore"])
  end

  private

  def genres_for(items)
    html = <<~HTML
      <div class="field-name-field-stil-taxo">
        <div class="field-items">
          #{items.map { |i| %(<div class="field-item">#{i}</div>) }.join("\n")}
        </div>
      </div>
    HTML
    Scrapers::Sedel.new.event_genres(Nokogiri::HTML.fragment(html))
  end
end
