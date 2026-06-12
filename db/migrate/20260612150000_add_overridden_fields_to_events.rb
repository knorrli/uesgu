class AddOverriddenFieldsToEvents < ActiveRecord::Migration[8.0]
  # The set of scalar fields an admin has manually edited and locked, so the
  # nightly re-scrape stops overwriting them (see Event#overridden? and
  # Scrapers::Agent#build_event). Field-level sibling of dismissed_at.
  def change
    add_column :events, :overridden_fields, :jsonb, default: [], null: false
  end
end
