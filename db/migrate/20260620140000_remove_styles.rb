# Phase 2b: the Style layer is gone — genres now form the taxonomy tree that
# replaced it. Drop the styles table, the Style↔Genre join, and every
# styles-context tagging on events. (No real users yet, so the dropped data
# needs no migration — it just goes; see the taxonomy redesign doc.)
class RemoveStyles < ActiveRecord::Migration[8.0]
  def up
    ActsAsTaggableOn::Tagging.where(context: "styles").delete_all
    drop_table :genres_styles
    drop_table :styles
  end

  def down
    create_table :styles do |t|
      t.string :name
      t.timestamps
    end

    create_table :genres_styles, id: false do |t|
      t.bigint :genre_id, null: false
      t.bigint :style_id, null: false
      t.index %i[genre_id style_id], unique: true
      t.index :style_id
    end
  end
end
