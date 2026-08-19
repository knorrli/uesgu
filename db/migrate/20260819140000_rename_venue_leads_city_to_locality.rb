class RenameVenueLeadsCityToLocality < ActiveRecord::Migration[8.1]
  # The middle tier of the location hierarchy was never only cities — the registry
  # already holds villages (Wabern, Rubigen). Renaming the column keeps the lead
  # inbox on the same vocabulary as the registry and the location taxonomy. Tag
  # values are untouched; this is a name change only.
  def change
    rename_column :venue_leads, :city, :locality
  end
end
