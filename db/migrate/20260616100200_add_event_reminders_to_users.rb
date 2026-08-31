class AddEventRemindersToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :event_reminders, :boolean, default: false, null: false
    add_column :users, :reminder_time, :integer, default: 720, null: false
    add_column :users, :reminder_lead_days, :integer, default: 0, null: false
    add_column :users, :last_reminded_on, :date
  end
end
