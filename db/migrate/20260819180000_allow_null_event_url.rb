class AllowNullEventUrl < ActiveRecord::Migration[8.1]
  # A user-captured event has no source page (docs/user-event-capture-design.md).
  # Nothing else has to change: dropping a NOT NULL is catalog-only in Postgres (no
  # rewrite, no scan), and index_events_on_url stands as-is, since a unique index
  # already permits unlimited NULLs.
  def change
    change_column_null :events, :url, true
  end
end
