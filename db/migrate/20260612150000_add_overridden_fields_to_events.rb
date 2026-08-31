class AddOverriddenFieldsToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :overridden_fields, :jsonb, default: [], null: false
  end
end
