class AddFoldedColumnsToPlaces < ActiveRecord::Migration[8.1]
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
    enable_extension :pg_trgm

    add_column :places, :name_folded, :virtual, type: :string,
               as: folded_sql("name"), stored: true
    add_column :places, :locality_folded, :virtual, type: :string,
               as: folded_sql("locality"), stored: true
  end
end
