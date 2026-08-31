require_relative "test_helper"
require "rails/test_help"

module TaxonomyFixtures
  def self.next_seq
    @seq = (@seq || 0) + 1
  end

  def genre(name: "zorptronic", events_count: 0, parent: nil)
    g = Genre.create!(name: "#{name}-#{TaxonomyFixtures.next_seq}", events_count: events_count)
    g.set_parent!(parent) if parent
    g
  end

  def event(**attrs)
    n = TaxonomyFixtures.next_seq
    Event.create!({
      title: "Synthetic Show #{n}",
      start_date: Date.new(2030, 1, 1),
      url: "https://fixture.test/#{n}"
    }.merge(attrs))
  end

  def event_with_genres(*genre_names)
    e = event
    e.genre_list = genre_names.flatten if genre_names.any?
    e.save!
    e
  end

  def genre_for(name)
    Genre.find_by(fingerprint: Genre.fingerprint_for(name))
  end

  def place(**attrs)
    n = TaxonomyFixtures.next_seq
    Place.create!({ name: "Zorpsaal #{n}", locality: "Zorpwil", canton: "BE" }.merge(attrs))
        .tap { Locality.reconcile! }
  end

  def user(**attrs)
    n = TaxonomyFixtures.next_seq
    User.create!({ username: "user#{n}", password: PASSWORD }.merge(attrs))
  end

  def invitation(**attrs)
    attrs[:created_by] ||= user(admin: true)
    Invitation.create!(attrs)
  end

  PASSWORD = "secret123"

  def sign_in_as(u, password: PASSWORD)
    post session_path, params: { username: u.username, password: password }
    u
  end
end

class ActiveSupport::TestCase
  include TaxonomyFixtures

  setup { I18n.locale = I18n.default_locale }
end
