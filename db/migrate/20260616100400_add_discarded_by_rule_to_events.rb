class AddDiscardedByRuleToEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :events, :discarded_by_rule, null: true, index: true,
                  foreign_key: { to_table: :discard_rules, on_delete: :nullify }
  end
end
