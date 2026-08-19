class RemoveLocalityFoldedFromPlaces < ActiveRecord::Migration[8.1]
  # locality_folded existed for one consumer: PlaceSuggester's trigram matching on
  # localities, removed in the same PR. Trigrams are weak on names that short — a
  # plain Luzren -> Luzern transposition scores 0.27 — so that field is served by an
  # exact fingerprint match in EventCapture::Creator instead, and its remaining
  # variants (Freiburg/Fribourg, Genf/Genève) need a curated alias list.
  #
  # name_folded stays: the place-name suggester is what the column pair was really
  # bought for, and it still runs.
  FOLDED_SQL = <<~SQL.squish.freeze
    btrim(
      regexp_replace(
        translate(
          replace(replace(lower(locality), '&', 'and'), '''n''', 'and'),
          'äöüàâéèêëïîôûç', 'aouaaeeeeiiouc'),
        '[^a-z0-9]+', ' ', 'g'))
  SQL

  def change
    remove_column :places, :locality_folded, :virtual, type: :string,
                  as: FOLDED_SQL, stored: true
  end
end
