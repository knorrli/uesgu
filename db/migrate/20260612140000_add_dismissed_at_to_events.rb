class AddDismissedAtToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :dismissed_at, :datetime
    add_index :events, :dismissed_at
  end
end
