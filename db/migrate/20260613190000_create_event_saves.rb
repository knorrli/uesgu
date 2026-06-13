# Per-user saved events ("save this show"). A simple join so a user can bookmark
# individual events (distinct from following locations/styles).
class CreateEventSaves < ActiveRecord::Migration[8.0]
  def change
    create_table :event_saves do |t|
      t.references :user, null: false, foreign_key: true
      t.references :event, null: false, foreign_key: true
      t.timestamps
    end
    add_index :event_saves, %i[user_id event_id], unique: true
  end
end
