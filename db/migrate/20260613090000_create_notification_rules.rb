class CreateNotificationRules < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_rules do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.boolean :enabled, null: false, default: true

      # WHEN — cadence + the wall-clock moment it fires. weekday (0=Sun..6=Sat)
      # applies to weekly/biweekly; monthday (1..28) to monthly. time_of_day is
      # minutes since local midnight (1050 = 17:30). last_fired_at is both the
      # de-dupe cursor and, for the "added" content type, the window floor.
      t.string :cadence, null: false, default: "weekly"
      t.integer :weekday
      t.integer :monthday
      t.integer :time_of_day, null: false, default: 1080 # 18:00
      t.datetime :last_fired_at

      # WHICH EVENTS — "added" = newly added since last fire (by created_at);
      # "happening" = events occurring in a window (by start_date). window holds
      # a Datepicker preset key (this_weekend, this_week, ...) for the latter.
      t.string :content_type, null: false, default: "added"
      t.string :window

      # WHICH FILTER — all / favorites (the user's followed locations OR styles) /
      # custom (the stored ransack-ish params: queries, style_list, location_list).
      t.string :scope, null: false, default: "favorites"
      t.jsonb :filter, null: false, default: {}

      # CHANNELS — the in-app inbox always receives a record; these add push and/or
      # email on top, per rule (a "just posted" alert may want push, a monthly
      # digest email-only).
      t.boolean :notify_push, null: false, default: true
      t.boolean :notify_email, null: false, default: false

      t.timestamps
    end

    add_index :notification_rules, %i[enabled cadence]

    # A fired rule writes a Notification (so the inbox + unread badge work for
    # every channel). Nullable rule ref keeps the legacy frequency-digest path
    # (Notification.generate_for) valid. event_ids is the snapshot the digest was
    # built from — robust across later rule edits/deletes; title is a frozen label
    # for display since the rule may be renamed or gone.
    add_reference :notifications, :notification_rule, foreign_key: true
    add_column :notifications, :event_ids, :jsonb, null: false, default: []
    add_column :notifications, :title, :string
  end
end
