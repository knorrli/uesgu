class RenameVenuePlacesToVenueLeads < ActiveRecord::Migration[8.0]
  def up
    rename_table :venue_places, :venue_leads
    add_column :venue_leads, :event_count, :integer, null: false, default: 0
    remove_index :venue_leads, column: %i[venue city canton]
    add_index :venue_leads, %i[source venue city canton], unique: true,
              name: "index_venue_leads_on_source_and_place"
  end

  def down
    remove_index :venue_leads, name: "index_venue_leads_on_source_and_place"
    add_index :venue_leads, %i[venue city canton], unique: true
    remove_column :venue_leads, :event_count
    rename_table :venue_leads, :venue_places
  end
end
