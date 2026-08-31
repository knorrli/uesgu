class AddCancelledAtToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :cancelled_at, :datetime
  end
end
