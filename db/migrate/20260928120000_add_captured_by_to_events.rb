class AddCapturedByToEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :events, :captured_by, null: true, index: true,
                                         foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
