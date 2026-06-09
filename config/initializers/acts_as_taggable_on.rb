ActsAsTaggableOn.remove_unused_tags = true

# monkey patched to allow ransack searches
module ActsAsTaggableOn
  class Tagging < ActsAsTaggableOn.base_class.constantize
    def self.ransackable_associations(auth_object = nil)
      ['tags']
    end

    def self.ransackable_attributes(auth_object = nil)
      ['context']
    end
  end

  class Tag < ActsAsTaggableOn.base_class.constantize
    def self.ransackable_associations(auth_object = nil)
      ['taggings']
    end

    def self.ransackable_attributes(auth_object = nil)
      ['name']
    end

    def to_combobox_display
      name
    end
  end
end
