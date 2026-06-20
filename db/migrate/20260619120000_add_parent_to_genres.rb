class AddParentToGenres < ActiveRecord::Migration[8.0]
  # A genre may point at a parent genre it sits under, forming a self-referential
  # tree (e.g. Rock > Punk > Crustpunk). This replaces the separate Style layer:
  # what were curated "styles" become root genres, and assigning a genre to a
  # style becomes setting its parent (see Genre#set_parent!). One primary parent
  # only — a tree, not a DAG (see docs/taxonomy-and-saved-filters-redesign.md).
  # Schema only; tree expansion and curation live on the Genre model + the
  # taxonomy:import_tree seed loader.
  def change
    add_reference :genres, :parent, foreign_key: { to_table: :genres }, null: true, index: true
    add_check_constraint :genres, 'parent_id IS NULL OR parent_id <> id',
                         name: 'genres_parent_not_self'
  end
end
