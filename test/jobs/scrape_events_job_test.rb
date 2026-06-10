require 'db_test_helper'

# The job resolves the scraper class, runs it, then reconciles genre usage so
# freshly scraped genres surface in the assignment queue. We stub the scraper
# with a double that "scrapes" one genre-tagged event and assert reconcile! ran.
class ScrapeEventsJobTest < ActiveSupport::TestCase
  class FakeScraper
    def self.call
      e = Event.create!(title: 'Scraped Show', start_date: Date.new(2030, 1, 1),
                        url: 'https://fixture.test/scraped')
      e.genre_list = ['scraped-genre']
      e.save!
    end
  end

  test 'perform runs the scraper and reconciles genre usage counts' do
    assert_not genre_for('scraped-genre')

    ScrapeEventsJob.new.perform(scraper_class: 'ScrapeEventsJobTest::FakeScraper')

    assert_equal 1, genre_for('scraped-genre').events_count,
                 'reconcile! ran after the scrape'
  end
end
