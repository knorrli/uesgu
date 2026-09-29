class AddMediaToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :media, :jsonb, default: [], null: false
  end
end
