require "test_helper"

class Scrapers::CancellationTest < Minitest::Test
  Event = Struct.new(:title, :description)

  CANCELLED = [
    "ABGESAGT",
    "Noche Cubana - ABGESAGT",
    "Konzert abgesagt",
    "Concert annulé",
    "Soirée annulée",
    "Annulation",
    "Concerto annullato",
    "Show cancelled",
    "Tour canceled"
  ].freeze

  NOT_CANCELLED = [
    "Fabian Cancellara Tribute",
    "Annie Lennox",
    "Annual Festival",
    "Konzert verschoben",
    "Spectacle reporté",         #
    "Ausverkauft",
    "Uncancellable Party"
  ].freeze

  def test_matches_cancellation_markers
    CANCELLED.each do |text|
      assert scraper.send(:event_cancelled?, Event.new(text, nil), nil),
             "expected #{text.inspect} to read as cancelled"
    end
  end

  def test_ignores_non_cancellation_text
    NOT_CANCELLED.each do |text|
      refute scraper.send(:event_cancelled?, Event.new(text, nil), nil),
             "expected #{text.inspect} NOT to read as cancelled"
    end
  end

  def test_detects_marker_in_description
    event = Event.new("Some Band", "Dieses Konzert wurde leider abgesagt")
    assert scraper.send(:event_cancelled?, event, nil)
  end

  private

  def scraper
    @scraper ||= Scrapers::Kofmehl.new
  end
end
