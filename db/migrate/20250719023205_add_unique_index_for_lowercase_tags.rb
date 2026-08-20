class AddUniqueIndexForLowercaseTags < ActiveRecord::Migration[8.0]
  def change
    add_index :tags, 'lower(name)', unique: true, name: 'index_tags_on_lower_name'
  end
end
