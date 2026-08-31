module LocationTagFold
  extend ActiveSupport::Concern

  private

  def variant_tag_names
    ActsAsTaggableOn::Tag.joins(:taggings)
                         .where(taggings: { context: "locations", taggable_type: Event.name })
                         .distinct.pluck(:name)
                         .select { |tag| Fingerprint.for(tag) == fingerprint }
  end

  def retag_events(add:, strip: [])
    variant_tag_names.each do |variant|
      next if add.include?(variant)

      Event.where(id: Event.tagged_with(variant, on: :locations).pluck(:id)).find_each do |event|
        event.location_list.remove(variant, *strip)
        event.location_list.add(*add)
        event.save!
      end
    end
  end

  def rewrite_saved_filters(canonical_name)
    SavedFilter.find_each do |saved|
      locations = saved.location_list
      rewritten = locations.map { |name| Fingerprint.for(name) == fingerprint ? canonical_name : name }.uniq
      next if rewritten == locations

      saved.filter = saved.filter.merge("location_list" => rewritten)
      redundant?(saved) ? saved.destroy! : saved.save!
    end
  end

  def redundant?(saved)
    saved.user.saved_filters.where.not(id: saved.id).any? { |other| other.fingerprint == saved.fingerprint }
  end
end
