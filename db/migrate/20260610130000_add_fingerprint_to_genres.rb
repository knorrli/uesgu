class AddFingerprintToGenres < ActiveRecord::Migration[8.0]
  FINGERPRINT_SQL = <<~SQL.squish.freeze
    regexp_replace(
      translate(
        replace(replace(lower(name), '&', 'and'), '''n''', 'and'),
        'äöüàâéèêëïîôûç', 'aouaaeeeeiiouc'),
      '[^a-z0-9]', '', 'g')
  SQL

  def change
    add_column :genres, :fingerprint, :virtual, type: :string, as: FINGERPRINT_SQL, stored: true
    add_index :genres, :fingerprint, unique: true, name: 'index_genres_on_fingerprint'
  end
end
