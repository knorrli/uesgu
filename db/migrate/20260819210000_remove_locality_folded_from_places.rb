class RemoveLocalityFoldedFromPlaces < ActiveRecord::Migration[8.1]
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
