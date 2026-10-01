class VenueFold
  def self.run! = new.run!

  def run!
    ActiveRecord::Base.transaction do
      retag_events
      rewrite_saved_filters
      LocationExclusion.rename_all { |name| venue_for(name)&.name }
      Place.where(fingerprint: venue_by_fingerprint.keys).destroy_all
    end
  end

  private

  def venue_by_fingerprint
    @venue_by_fingerprint ||= Location.taxonomy_venues.each_with_object({}) do |venue, map|
      venue.known_names.each { |name| map[Fingerprint.for(name)] = venue }
    end
  end

  def venue_for(name) = venue_by_fingerprint[Fingerprint.for(name)]

  def retag_events
    location_tag_names.each do |tag|
      venue = venue_for(tag)
      next if venue.nil? || tag == venue.name

      Event.where(id: Event.tagged_with(tag, on: :locations).pluck(:id)).find_each do |event|
        event.location_list.remove(tag)
        event.location_list.add(*venue.place_tuple)
        event.save!
      end
    end
  end

  def location_tag_names
    ActsAsTaggableOn::Tag.joins(:taggings)
                         .where(taggings: { context: "locations", taggable_type: Event.name })
                         .distinct.pluck(:name)
  end

  def rewrite_saved_filters
    SavedFilter.find_each do |saved|
      locations = saved.location_list
      rewritten = locations.map { |name| venue_for(name)&.name || name }.uniq
      next if rewritten == locations

      saved.filter = saved.filter.merge("location_list" => rewritten)
      redundant?(saved) ? saved.destroy! : saved.save!
    end
  end

  def redundant?(saved)
    saved.user.saved_filters.where.not(id: saved.id).any? { |other| other.fingerprint == saved.fingerprint }
  end
end
