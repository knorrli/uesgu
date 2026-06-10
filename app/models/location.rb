# Location tags (the `:locations` acts_as_taggable_on context on Event) are flat:
# a single tag list mixing venues, cities, and canton codes. There is no stored
# type. We DERIVE the type from the scrapers, which are the source of truth — each
# scraper represents one venue and declares its place as
# `[venue, *aliases, city, canton_code]` (see app/services/scrapers/*).
#
# All scrapers are force-loaded at boot (config/application.rb), so the lists below
# are always complete and stay in sync automatically when a scraper is added.
class Location
  include ActiveModel::Model

  # The venues our scrapers cover (== each scraper's `self.location`).
  def self.venue_names
    Scrapers::All.scrapers.values.map(&:location).to_set
  end

  # The canton codes our scrapers cover (== each scraper's last location element).
  def self.canton_codes
    Scrapers::All.scrapers.values.map { |scraper| scraper.locations.last }.to_set
  end

  # :venue for a concrete venue, :canton for a canton code, :city otherwise. The
  # canton code is the last element each scraper declares; anything else that is
  # not a venue is treated as a city.
  def self.type_for(name)
    name = name.to_s
    return :venue if venue_names.include?(name)
    return :canton if canton_codes.include?(name)

    :city
  end

  def self.venue?(name)
    venue_names.include?(name.to_s)
  end

  # Grouped tree for the favorites UI, derived from each scraper's locations array:
  #   { "BE" => { "Bern" => ["Dachstock", "Gaskessel", ...] }, ... }
  def self.hierarchy
    Scrapers::All.scrapers.values.each_with_object({}) do |scraper, tree|
      locations = scraper.locations
      canton = locations.last
      city = locations[-2]
      tree[canton] ||= {}
      (tree[canton][city] ||= []) << scraper.location
    end
  end
end
