class CreatePlaces < ActiveRecord::Migration[8.1]
  FINGERPRINT_SQL = <<~SQL.squish.freeze
    regexp_replace(
      translate(
        replace(replace(lower(name), '&', 'and'), '''n''', 'and'),
        'äöüàâéèêëïîôûç', 'aouaaeeeeiiouc'),
      '[^a-z0-9]', '', 'g')
  SQL

  def change
    create_table :places do |t|
      t.string :name, null: false
      t.virtual :fingerprint, type: :string, as: FINGERPRINT_SQL, stored: true
      t.string :locality, null: false
      t.string :canton, null: false
      t.string :url
      t.references :canonical, foreign_key: { to_table: :places }
      t.timestamps
    end

    add_index :places, :fingerprint, unique: true
    add_check_constraint :places, "canonical_id IS NULL OR canonical_id <> id",
                         name: "places_canonical_not_self"
  end
end
