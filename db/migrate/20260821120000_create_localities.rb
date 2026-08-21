class CreateLocalities < ActiveRecord::Migration[8.1]
  # The middle tier of the WHERE tree, given rows at last. Until now a locality was
  # a bare string in three places at once — places.locality, the venue registry's
  # `place:` block, and a flat location tag on every event — so "is Freiburg the same
  # town as Fribourg" had nowhere to be answered and Location.hierarchy grouped on
  # the literal string, splitting one town into two nodes.
  #
  # `fingerprint` MUST stay character-identical to the genres and places columns and
  # to Fingerprint.for, which reproduces it in Ruby for raw strings that have no row
  # yet. STORED + IMMUTABLE-only functions, so translate() over a fixed accent set
  # rather than unaccent().
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
      # Nullable, unlike places.canton: Buchs is a locality in SG, AG, ZH and LU
      # alike, and a row that has to pick one would file events under a branch of
      # the tree nobody looking for them will open. NULL is "we abstain".
      t.string :canton
      # Cached count of events whose location tags carry this name, refreshed by
      # Locality.reconcile!. Drives the admin browser's ordering.
      t.integer :events_count, null: false, default: 0
      # An alias points at the locality it is a name for ("Bienne" → "Biel"). Unlike
      # the genre equivalent this is not only a query-time link: Locality#merge_into!
      # repoints the taggings too, because the WHERE tree groups on literal strings.
      t.references :canonical, foreign_key: { to_table: :localities }
      t.timestamps
    end

    add_index :localities, :fingerprint, unique: true
    add_check_constraint :localities, "canonical_id IS NULL OR canonical_id <> id",
                         name: "localities_canonical_not_self"
  end
end
