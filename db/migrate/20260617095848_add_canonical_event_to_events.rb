class AddCanonicalEventToEvents < ActiveRecord::Migration[8.0]
  def change
    # Non-destructive event dedup: a duplicate (e.g. our bespoke Kofmehl scrape of
    # a show PETZI also lists) points at its canonical (the PETZI event). Duplicates
    # are never deleted — bookmarks (event_saves) stay intact — they're just hidden
    # from listings via Event.visible. on_delete: :nullify so deleting a canonical
    # frees its duplicates rather than cascading.
    add_reference :events, :canonical_event, null: true, index: true,
                  foreign_key: { to_table: :events, on_delete: :nullify }
    add_check_constraint :events, 'canonical_event_id IS NULL OR canonical_event_id <> id',
                         name: 'events_canonical_not_self'
  end
end
