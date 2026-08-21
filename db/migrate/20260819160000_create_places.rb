class CreatePlaces < ActiveRecord::Migration[8.1]
  # Captured places: the complement of the venue registry (config/venues.yml) —
  # where a user-captured event happens when we don't source that venue.
  #
  # `fingerprint` MUST stay character-identical to the genres column
  # (AddFingerprintToGenres) and to Fingerprint.for, which reproduces it in Ruby
  # for matching raw strings that have no row yet. STORED + IMMUTABLE-only
  # functions, so translate() over a fixed accent set rather than unaccent().
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
      # Both tiers are NOT NULL because a place exists only to be a location, and
      # Location.add_to_tree drops any tuple missing one — optional would hide the
      # events most likely to need the WHERE tree (the field, the barn, the forest).
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
