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

  # A persisted Event tagged with the given invented genre names. Satisfies the
  # title/start_date/url presence validations with throwaway values.
  def event_with_genres(*genre_names)
    e = Event.new(
      title: "Synthetic Show #{TaxonomyFixtures.next_seq}",
      start_date: Date.new(2030, 1, 1),
      url: "https://fixture.test/#{TaxonomyFixtures.next_seq}"
    )
    e.genre_list = genre_names.flatten if genre_names.any?
    e.save!
    e
  end
end

class ActiveSupport::TestCase
  include TaxonomyFixtures
end
