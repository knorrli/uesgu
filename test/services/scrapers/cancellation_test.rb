require "test_helper"

# Locks the cancellation-marker behaviour independent of fixtures: the multilingual
# keyword set, the letter-boundary guards against false positives, and the fact that
# the default reads the extracted title/description (not full HTML).
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
    "Fabian Cancellara Tribute", # contains "cancell" but not "cancelled"
    "Annie Lennox",              # "ann…" but not a marker
    "Annual Festival",           # "annu…al", not "annul…"
    "Konzert verschoben",        # postponed is NOT cancelled
    "Spectacle reporté",         # postponed (FR) is NOT cancelled
    "Ausverkauft",               # sold out is NOT cancelled
    "Uncancellable Party"        # marker embedded in a longer word
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
