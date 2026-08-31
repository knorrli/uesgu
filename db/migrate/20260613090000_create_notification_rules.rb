class CreateNotificationRules < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_rules do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.boolean :enabled, null: false, default: true

      t.string :cadence, null: false, default: "weekly"
      t.integer :weekday
      t.integer :monthday
      t.integer :time_of_day, null: false, default: 1080
      t.datetime :last_fired_at

      t.string :content_type, null: false, default: "added"
      t.string :window

      t.string :scope, null: false, default: "favorites"
      t.jsonb :filter, null: false, default: {}

      t.boolean :notify_push, null: false, default: true
      t.boolean :notify_email, null: false, default: false

      t.timestamps
    end

    add_index :notification_rules, %i[enabled cadence]

    add_reference :notifications, :notification_rule, foreign_key: true
    add_column :notifications, :event_ids, :jsonb, null: false, default: []
    add_column :notifications, :title, :string
  end
end
