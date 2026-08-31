require "test_helper"

class Scrapers::RescheduleTest < Minitest::Test
  Event = Struct.new(:title, :description)

  RESCHEDULED = [
    "Konzert verschoben",
    "Show verlegt",
    "NEUES DATUM / NEW DATE: DeathbyRomy",
    "Neuer Termin",
    "Spectacle reporté",
    "Soirée reportée",
    "Nouvelle date",
    "Concerto rinviato",
    "Spettacolo posticipato",
    "Tour postponed",
    "Festival rescheduled — new date"
  ].freeze

  NOT_RESCHEDULED = [
    "Konzert abgesagt",
    "Concert annulé",            #
    "Reportage Festival",
    "Annual Report",
    "Renew date drive",
    "Newsworthy Datum",
    "Ausverkauft"
  ].freeze

  def test_matches_reschedule_markers
    RESCHEDULED.each do |text|
      assert scraper.send(:event_rescheduled?, Event.new(text, nil), nil),
             "expected #{text.inspect} to read as rescheduled"
    end
  end

  def test_ignores_non_reschedule_text
    NOT_RESCHEDULED.each do |text|
      refute scraper.send(:event_rescheduled?, Event.new(text, nil), nil),
             "expected #{text.inspect} NOT to read as rescheduled"
    end
  end

  def test_detects_marker_in_description
    event = Event.new("Some Band", "Achtung: dieses Konzert wurde verschoben")
    assert scraper.send(:event_rescheduled?, event, nil)
  end

  def test_cancellation_and_reschedule_are_disjoint
    cancelled = Event.new("Konzert abgesagt", nil)
    refute scraper.send(:event_rescheduled?, cancelled, nil)

    rescheduled = Event.new("Konzert verschoben", nil)
    refute scraper.send(:event_cancelled?, rescheduled, nil)
  end

  private

  def scraper
    @scraper ||= Scrapers::Kofmehl.new
  end
end
