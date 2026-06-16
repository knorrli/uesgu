class AddDiscardedByRuleToEvents < ActiveRecord::Migration[8.0]
  def change
    # Which discard rule currently filters this event out of public listings
    # (nil = not discarded). Re-derived every scrape and on any rule change, so
    # on_delete: :nullify keeps it consistent if a rule is destroyed.
    add_reference :events, :discarded_by_rule, null: true, index: true,
                  foreign_key: { to_table: :discard_rules, on_delete: :nullify }
  end
end
