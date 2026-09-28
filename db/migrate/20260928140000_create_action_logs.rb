class CreateActionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :action_logs do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :action, null: false
      t.string :area, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.string :subject_label
      t.jsonb :before, null: false, default: {}
      t.jsonb :details, null: false, default: {}
      t.references :reverts, foreign_key: { to_table: :action_logs }
      t.timestamps
    end
    add_index :action_logs, %i[subject_type subject_id id]
    add_index :action_logs, :area
  end
end
