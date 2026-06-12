class CreatePushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true

      # The push-service URL the browser hands us, plus the two keys needed to
      # encrypt payloads for it. endpoint is the natural identity of a device's
      # subscription, so it's unique and used to upsert on re-subscribe.
      t.string :endpoint, null: false
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false

      # For the "your devices" list in settings; lets a user tell subscriptions
      # apart. Nullable — the browser may not send a User-Agent.
      t.string :user_agent

      # Last successful push, for pruning/diagnostics.
      t.datetime :last_pushed_at

      t.timestamps
    end

    add_index :push_subscriptions, :endpoint, unique: true
  end
end
