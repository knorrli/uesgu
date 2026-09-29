require "test_helper"

class Scrapers::OnoTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/scrapers/ono/list.html", __dir__)

  def test_media_comes_from_the_playlist_in_the_json_ld_description_not_the_channel_link
    row = Nokogiri::HTML(File.read(FIXTURE)).css("#evcal_list .eventon_list_event")
                  .find { |r| r.at_css(".evcal_event_title")&.text.to_s.squish.start_with?("MAJA BACKOVIC") }

    assert_equal [{ "provider" => "youtube", "id" => "fHGccI82Ovo" }], Scrapers::Ono.new.send(:event_media, row)
  end
end
