class CreateLocalities < ActiveRecord::Migration[8.1]
  FINGERPRINT_SQL = <<~SQL.squish.freeze
    regexp_replace(
      translate(
        replace(replace(lower(name), '&', 'and'), '''n''', 'and'),
        'äöüàâéèêëïîôûç', 'aouaaeeeeiiouc'),
      '[^a-z0-9]', '', 'g')
  SQL

  def change
    create_table :localities do |t|
      t.string :name, null: false
      t.virtual :fingerprint, type: :string, as: FINGERPRINT_SQL, stored: true
      t.string :canton
      t.integer :events_count, null: false, default: 0
      t.references :canonical, foreign_key: { to_table: :localities }
      t.timestamps
    end

    add_index :localities, :fingerprint, unique: true
    add_check_constraint :localities, "canonical_id IS NULL OR canonical_id <> id",
                         name: "localities_canonical_not_self"
  end
end
