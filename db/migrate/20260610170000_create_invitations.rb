class CreateInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :invitations do |t|
      t.string :code, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :redeemed_by, foreign_key: { to_table: :users }
      t.datetime :redeemed_at
      t.string :note
      t.datetime :expires_at
      t.timestamps
    end

    add_index :invitations, :code, unique: true
  end
end
