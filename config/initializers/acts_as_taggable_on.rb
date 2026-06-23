ActsAsTaggableOn.remove_unused_tags = true

# Case-SENSITIVE tag matching. Every tag source now produces a consistent casing
# on its own — genres via Genre.canonicalize_names (fingerprint-backed), styles
# from the fixed Style set, locations from each scraper's hardcoded
# [venue, city, canton] — so the global case-insensitive dedup is redundant, and
# it was actively harmful: it shared one row across contexts, e.g. the Fribourg
# canton location "FR" shadowing the artist-origin genre "Fr". Strict matching
# keeps "FR" (canton) and "Fr" (genre) as distinct tags. NOTE: this trades a
# safety net for a discipline — any new tag source must self-normalize its
# casing. Paired with dropping the unique lower(name) index on tags (see
# DropCaseInsensitiveTagIndex); the case-sensitive unique index_tags_on_name
# becomes the enforcement.
ActsAsTaggableOn.strict_case_match = true

# monkey patched to allow ransack searches
module ActsAsTaggableOn
  class Tagging < ActsAsTaggableOn.base_class.constantize
    def self.ransackable_associations(auth_object = nil)
      ["tags"]
    end

    def self.ransackable_attributes(auth_object = nil)
      ["context"]
    end
  end

  class Tag < ActsAsTaggableOn.base_class.constantize
    def self.ransackable_associations(auth_object = nil)
      ["taggings"]
    end

    def self.ransackable_attributes(auth_object = nil)
      ["name"]
    end

    def to_combobox_display
      name
    end
  end
end
