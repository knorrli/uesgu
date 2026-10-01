class CreateLocationExclusions < ActiveRecord::Migration[8.1]
  def change
    create_table :location_exclusions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :location_exclusions, %i[user_id name], unique: true
  end
end
