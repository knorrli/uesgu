require 'test_helper'

# ISC's detail pages omit the year, so Scrapers::Isc infers it from the scrape
# date — the club only ever lists upcoming concerts, so a day/month already past
# in the current year belongs to next year. Regression guard for the Dec->Jan
# boundary, where a leading next-year event used to keep the scrape year and land
# ~12 months in the past (nothing preceded it to trigger the old backward-wrap).
class Scrapers::IscTest < ActiveSupport::TestCase
  test 'an upcoming date later this year keeps the scrape year' do
    assert_equal 2026, start_time_for('20.06.', on: Date.new(2026, 6, 15)).year
  end

  test 'a January event scraped in December rolls into next year' do
    assert_equal 2027, start_time_for('05.01.', on: Date.new(2026, 12, 28)).year
  end

  test 'a late-December event scraped in December stays this year' do
    assert_equal 2026, start_time_for('30.12.', on: Date.new(2026, 12, 28)).year
  end

  test 'a date already past this year is read as next year' do
    assert_equal 2027, start_time_for('10.06.', on: Date.new(2026, 6, 15)).year
  end

  test 'parses the day, month and time alongside the inferred year' do
    t = start_time_for('05.01.', on: Date.new(2026, 12, 28))
    assert_equal [2027, 1, 5, 20, 0], [t.year, t.month, t.day, t.hour, t.min]
  end

  private

  # Build the minimal detail-page markup Isc#event_start_time reads, frozen to the
  # given scrape date (the scraper snapshots Date.current at construction).
  def start_time_for(date, on:, time: '20:00 Uhr')
    content = Nokogiri::HTML(<<~HTML)
      <div class="event_detail_header"><span class="event_title_date">#{date}</span></div>
      <div class="event_detail"><span class="facts_listing">#{time}</span></div>
    HTML

    travel_to(on) { Scrapers::Isc.new.event_start_time(content) }
  end
end
