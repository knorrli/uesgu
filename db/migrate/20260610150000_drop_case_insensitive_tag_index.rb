class DropCaseInsensitiveTagIndex < ActiveRecord::Migration[8.0]
  def up
    remove_index :tags, name: 'index_tags_on_lower_name'
  end

  def down
    add_index :tags, 'lower((name)::text)', unique: true, name: 'index_tags_on_lower_name'
  end
end
