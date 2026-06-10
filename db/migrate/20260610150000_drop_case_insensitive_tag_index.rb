class DropCaseInsensitiveTagIndex < ActiveRecord::Migration[8.0]
  # Drop the UNIQUE lower(name) index on tags so case-variant tags can coexist
  # (e.g. the "FR" canton location and the "Fr" artist-origin genre). The
  # case-sensitive UNIQUE index_tags_on_name stays and becomes the sole
  # uniqueness enforcement, matching ActsAsTaggableOn.strict_case_match = true.
  # Schema only. Reverting requires case-consistent tag data.
  def up
    remove_index :tags, name: 'index_tags_on_lower_name'
  end

  def down
    add_index :tags, 'lower((name)::text)', unique: true, name: 'index_tags_on_lower_name'
  end
end
