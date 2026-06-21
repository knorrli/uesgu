require 'db_test_helper'

# VenuePlace stores the [venue, city, canton] tuples a per-event aggregator
# resolves at scrape time, so Location can fold them into the taxonomy (the role
# info is lost once AATO flattens the tags on the event). Synthetic names
# (project-test-synthetic-taxonomy).
class VenuePlaceTest < ActiveSupport::TestCase
  test 'record! is idempotent on the same tuple' do
    2.times do
      VenuePlace.record!(venue: 'Glorphalle', city: 'Snarftown', canton: 'BE',
                         source: 'OLE:Test')
    end
    assert_equal 1, VenuePlace.where(venue: 'Glorphalle').count
  end

  test 'a different city for the same venue is a distinct row' do
    VenuePlace.record!(venue: 'Glorphalle', city: 'Snarftown', canton: 'BE', source: 'OLE:Test')
    VenuePlace.record!(venue: 'Glorphalle', city: 'Blipcity', canton: 'ZH', source: 'OLE:Test')
    assert_equal 2, VenuePlace.where(venue: 'Glorphalle').count
  end

  test 'venue and source are required' do
    assert_raises(ActiveRecord::RecordInvalid) do
      VenuePlace.create!(venue: nil, city: 'X', canton: 'BE', source: 'OLE:Test')
    end
  end
end
