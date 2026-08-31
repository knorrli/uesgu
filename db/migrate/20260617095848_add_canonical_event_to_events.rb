class AddCanonicalEventToEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :events, :canonical_event, null: true, index: true,
                  foreign_key: { to_table: :events, on_delete: :nullify }
    add_check_constraint :events, 'canonical_event_id IS NULL OR canonical_event_id <> id',
                         name: 'events_canonical_not_self'
  end
end
