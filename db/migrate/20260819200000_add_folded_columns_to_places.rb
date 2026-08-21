class AddFoldedColumnsToPlaces < ActiveRecord::Migration[8.1]
  # Match-at-entry scores names with pg_trgm's word_similarity, which compares the
  # query against WORDS in the target — and the deciding case is a subset, not a
  # typo ("Quartierfest" against an existing "Marzili Quartierfest"). The
  # fingerprint cannot carry that comparison: it strips separators entirely, so
  # "Marzili Quartierfest" collapses to one word and word_similarity degrades to
  # plain similarity. Hence a second generated column per compared field, folding
  # separators TO SPACES where the fingerprint folds them AWAY — one clause apart,
  # same IMMUTABLE-only rules (translate() over a fixed accent set, never
  # unaccent()).
  #
  # Both must stay character-identical to Fingerprint.folded, which reproduces them
  # in Ruby for the query string and for registry venues, which have no row here.
  def folded_sql(column)
    <<~SQL.squish
      btrim(
        regexp_replace(
          translate(
            replace(replace(lower(#{column}), '&', 'and'), '''n''', 'and'),
            'äöüàâéèêëïîôûç', 'aouaaeeeeiiouc'),
          '[^a-z0-9]+', ' ', 'g'))
    SQL
  end

  def change
    # For the MEASURE, not for speed: places is a tens-of-rows table where a
    # sequential scan is free, so there is deliberately no GIN index to "optimise"
    # around later.
    enable_extension :pg_trgm

    add_column :places, :name_folded, :virtual, type: :string,
               as: folded_sql("name"), stored: true
    add_column :places, :locality_folded, :virtual, type: :string,
               as: folded_sql("locality"), stored: true
  end
end
