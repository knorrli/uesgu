class DropFilters < ActiveRecord::Migration[8.0]
  def up
    drop_table :filters
  end

  def down
    create_table :filters do |t|
      t.string :name
      t.jsonb :queries, default: []
      t.jsonb :date_ranges, default: []

      t.timestamps
    end
  end
end
