class RenameVenueLeadsCityToLocality < ActiveRecord::Migration[8.1]
  def change
    rename_column :venue_leads, :city, :locality
  end
end
