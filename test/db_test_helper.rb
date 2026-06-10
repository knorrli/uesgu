# DB-backed test helper.
#
# Deliberately separate from test_helper.rb, which is DB-free so the offline
# scraper golden/cancellation suites stay fast and schema-independent. Model,
# presenter, and job tests that need the database require THIS file instead: it
# layers Rails' `rails/test_help` on top (transactional tests, schema upkeep,
# ActiveSupport::TestCase) without coupling the scraper suites to the DB.
#
# Taxonomy rule (see project memory): assert against *mechanics* using invented
# genre/style names only — never real taxonomy content — so taxonomy edits in
# the parallel refactor can't break these tests. The TaxonomyFixtures helper
# below makes the synthetic data obvious at every call site.
require_relative 'test_helper'
require 'rails/test_help'

module TaxonomyFixtures
  # Monotonic suffix so repeated calls in one test never collide on the unique
  # lower(name) index, while staying deterministic (no Time/random — both are
  # unavailable in this harness and would defeat reproducibility).
  def self.next_seq
    @seq = (@seq || 0) + 1
  end

  # A curated Style with an invented name (e.g. "wubstep-1").
  def style(name: "wubstep")
    Style.create!(name: "#{name}-#{TaxonomyFixtures.next_seq}")
  end

  # A raw Genre row with an invented name. Pass events_count: to simulate usage
  # without having to tag real events (events_count is reconciled, not a
  # counter-cache), or styles: to pre-map it.
  def genre(name: "zorptronic", events_count: 0, styles: [])
    g = Genre.create!(name: "#{name}-#{TaxonomyFixtures.next_seq}", events_count: events_count)
    g.styles = Array(styles) if styles.present?
    g
  end

  # A persisted Event with throwaway-but-valid title/start_date/url. Extra attrs
  # (created_at, hidden, cancelled_at, start_date, location_list, ...) override
  # the defaults — created_at is honoured by Rails when set explicitly, which
  # lets digest/window tests place events at precise points in time.
  def event(**attrs)
    n = TaxonomyFixtures.next_seq
    Event.create!({
      title: "Synthetic Show #{n}",
      start_date: Date.new(2030, 1, 1),
      url: "https://fixture.test/#{n}"
    }.merge(attrs))
  end

  # A persisted Event tagged with the given invented genre names.
  def event_with_genres(*genre_names)
    e = event
    e.genre_list = genre_names.flatten if genre_names.any?
    e.save!
    e
  end

  # A persisted User with a valid synthetic username + password. Pass attrs to
  # set notification_frequency, last_notified_at, created_at, email_address, etc.
  def user(**attrs)
    n = TaxonomyFixtures.next_seq
    User.create!({ username: "user#{n}", password: PASSWORD }.merge(attrs))
  end

  PASSWORD = 'secret123'

  # Integration-test sign-in: drive the real session-create flow so the signed
  # cookie is set in the test's cookie jar. Only meaningful inside an
  # ActionDispatch::IntegrationTest (uses post/session_path).
  def sign_in_as(u, password: PASSWORD)
    post session_path, params: { username: u.username, password: password }
    u
  end
end

class ActiveSupport::TestCase
  include TaxonomyFixtures
end
