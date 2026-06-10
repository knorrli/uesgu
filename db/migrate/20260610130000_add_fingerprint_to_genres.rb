class AddFingerprintToGenres < ActiveRecord::Migration[8.0]
  # A normalized matching key: lowercase, &→and, 'n'→and, accents folded, then
  # every non-alphanumeric stripped. Mechanical spelling variants (case, spaces,
  # hyphens, punctuation, "Hip Hop"/"Hip-Hop"/"HipHop") collapse to one key, so a
  # scraped genre resolves to the right Genre/Style with zero per-variant upkeep.
  #
  # STORED generated column (not a Ruby callback): it's joined/indexed in SQL and
  # must never drift, even under raw upsert_all. Every function used is IMMUTABLE
  # (required by STORED) — note translate() over a fixed accent set rather than
  # unaccent(), which is not IMMUTABLE.
  #
  # IMPORTANT: Genre.fingerprint_for(str) MUST reproduce this expression exactly
  # (verified by a parity test) — it's used at ingest time on raw strings that
  # have no row to read this column from.
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
