class CreateVenuePlaces < ActiveRecord::Migration[8.0]
  def change
    create_table :venue_places do |t|
      t.string :venue,  null: false
      t.string :city
      t.string :canton
      t.string :source, null: false
      t.timestamps
    end
    add_index :venue_places, %i[venue city canton], unique: true
  end
end
