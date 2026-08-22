# The rewrite half of a location merge, shared by the two vocabularies that own a
# location tag: Locality (the town) and Place (the captured venue).
#
# Folding one row into another REWRITES the taggings rather than resolving the alias
# at query time, and deliberately: Location.hierarchy, Location.usage, the filter-tree
# pruning in TagsHelper#location_filter_tree and Filter#location_list all group on the
# literal tag string. A link that repoints nothing leaves the town or the venue split
# across two nodes of the WHERE tree holding half the events each — the thing the
# merge is asked to fix.
#
# Requires the including model to expose `fingerprint` (the stored generated column
# both tables carry).
module LocationTagFold
  extend ActiveSupport::Concern

  private

  # Every location tag that folds onto this row, not just its own spelling: a tag
  # minted before entry-time normalisation existed ("bern") shares this fingerprint
  # and has to travel with it.
  def variant_tag_names
    ActsAsTaggableOn::Tag.joins(:taggings)
                         .where(taggings: { context: "locations", taggable_type: Event.name })
                         .distinct.pluck(:name)
                         .select { |tag| Fingerprint.for(tag) == fingerprint }
  end

  # `add` is every tag the target row puts on an event; `strip` is what this row put
  # there beyond its own name — a place also tags its town and its canton, a locality
  # tags only itself. Where the two rows agree on a tag it is removed and re-added,
  # which costs nothing and keeps the caller from having to diff them.
  #
  # Snapshot the ids first: removing the tag shrinks the tagged_with set find_each
  # would page over, which would skip events and leave them on the old name.
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

  # A saved filter's location names are a jsonb snapshot frozen at save time and
  # matched as literal strings (see SavedFilter), so one left on the old name matches
  # nothing the moment the events move — silently, in the saved scope, the digest and
  # the feed highlighting alike.
  def rewrite_saved_filters(canonical_name)
    SavedFilter.find_each do |saved|
      locations = saved.location_list
      rewritten = locations.map { |name| Fingerprint.for(name) == fingerprint ? canonical_name : name }.uniq
      next if rewritten == locations

      saved.filter = saved.filter.merge("location_list" => rewritten)
      redundant?(saved) ? saved.destroy! : saved.save!
    end
  end

  # The rewrite can land a filter on a scope its owner already saved under the
  # canonical spelling, which the one-filter-per-fingerprint rule forbids — dropping
  # the copy that carries the merged-away name keeps the merge from failing that
  # validation, and leaves the older filter's schedule and firing history intact.
  def redundant?(saved)
    saved.user.saved_filters.where.not(id: saved.id).any? { |other| other.fingerprint == saved.fingerprint }
  end
end
