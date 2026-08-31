class AddRescheduledAtToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :rescheduled_at, :datetime
  end
end
