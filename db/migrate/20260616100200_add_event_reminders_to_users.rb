class AddEventRemindersToUsers < ActiveRecord::Migration[8.0]
  def change
    # Global opt-in: a daily nudge about the shows you've saved.
    add_column :users, :event_reminders, :boolean, default: false, null: false
    # When the nudge goes out — minutes since midnight, local time. Default noon.
    # No UI to change it yet; the column lets us make it customizable later.
    add_column :users, :reminder_time, :integer, default: 720, null: false
    # How many days ahead to look: 0 = the day of the show, 1 = the day before.
    # Stored now (default day-of); the picker comes later.
    add_column :users, :reminder_lead_days, :integer, default: 0, null: false
    # Fire-once-a-day guard for the quarter-hourly sweep.
    add_column :users, :last_reminded_on, :date
  end
end
