class CreateInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :invitations do |t|
      # The shareable code a friend redeems at signup. Stored unformatted and
      # upper-cased; views group it (ABCD-2345) for legibility.
      t.string :code, null: false
      # Who minted it (an admin) and, once spent, who used it.
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :redeemed_by, foreign_key: { to_table: :users }
      t.datetime :redeemed_at
      # Optional admin memo ("for Anna") and optional expiry.
      t.string :note
      t.datetime :expires_at
      t.timestamps
    end

    add_index :invitations, :code, unique: true
  end
end
