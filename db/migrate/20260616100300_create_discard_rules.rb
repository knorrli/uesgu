class CreateDiscardRules < ActiveRecord::Migration[8.0]
  def change
    create_table :discard_rules do |t|
      # Case-insensitive substring matched against an event's title/subtitle.
      t.string :pattern, null: false
      # Venue scope: a scraper's location name, or nil for all venues.
      t.string :scraper
      t.boolean :active, null: false, default: true
      # Free-text admin reminder of what this rule is for.
      t.string :note

      t.timestamps
    end
  end
end
