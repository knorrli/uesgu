require 'test_helper'

# Locks the reschedule-marker behaviour (the counterpart to CancellationTest): the
# multilingual keyword set, the letter-boundary guards against false positives, the
# "new date" phrases, and the fact that cancellation markers are NOT reschedules
# (and vice versa) — the two are deliberately disjoint.
class Scrapers::RescheduleTest < Minitest::Test
  Event = Struct.new(:title, :subtitle)

  RESCHEDULED = [
    'Konzert verschoben',
    'Show verlegt',
    'NEUES DATUM / NEW DATE: DeathbyRomy', # the real-world motivating case
    'Neuer Termin',
    'Spectacle reporté',
    'Soirée reportée',
    'Nouvelle date',
    'Concerto rinviato',
    'Spettacolo posticipato',
    'Tour postponed',
    'Festival rescheduled — new date'
  ].freeze

  NOT_RESCHEDULED = [
    'Konzert abgesagt',          # cancelled is NOT rescheduled
    'Concert annulé',            # cancelled (FR) is NOT rescheduled
    'Reportage Festival',        # "report…age", not the accented marker
    'Annual Report',             # English "report" (no accent) is not a marker
    'Renew date drive',          # "new date" embedded after "re" — boundary guards it
    'Newsworthy Datum',          # not the "neues datum" phrase
    'Ausverkauft'                # sold out is neither
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

  def test_detects_marker_in_subtitle
    event = Event.new('Some Band', 'Achtung: dieses Konzert wurde verschoben')
    assert scraper.send(:event_rescheduled?, event, nil)
  end

  # The two status markers are disjoint: a cancelled show must not also read as
  # rescheduled, and a rescheduled show must not read as cancelled.
  def test_cancellation_and_reschedule_are_disjoint
    cancelled = Event.new('Konzert abgesagt', nil)
    refute scraper.send(:event_rescheduled?, cancelled, nil)

    rescheduled = Event.new('Konzert verschoben', nil)
    refute scraper.send(:event_cancelled?, rescheduled, nil)
  end

  private

  def scraper
    @scraper ||= Scrapers::Kofmehl.new
  end
end
