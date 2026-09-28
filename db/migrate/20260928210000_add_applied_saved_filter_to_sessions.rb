class AddAppliedSavedFilterToSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :sessions, :applied_saved_filter,
                  foreign_key: { to_table: :saved_filters, on_delete: :nullify }
  end
end
