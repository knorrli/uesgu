require "test_helper"

class Scrapers::SedelTest < Minitest::Test
  CASES = {
    "Punk Rock"                                     => ["Punk Rock"],
    "Fast Palm-Muted Chugcore / Post-Hardcore"      => ["Fast Palm-Muted Chugcore", "Post-Hardcore"],
    "Darkgaze | Blackwave"                          => ["Darkgaze", "Blackwave"],
    "Folkpunk/Polka"                                => ["Folkpunk", "Polka"],
    "Garage-Punk-n-Roll"                            => ["Garage-Punk-n-Roll"],
    "EBM / New Beat"                                => ["EBM", "New Beat"],
    ""                                              => []
  }.freeze

  def test_splits_combined_genre_terms_on_slash_and_pipe
    CASES.each do |raw, expected|
      assert_equal expected, genres_for([raw]), "term #{raw.inspect}"
    end
  end

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
