class CreateExtractionFieldOutcomes < ActiveRecord::Migration[8.1]
  def change
    create_table :extraction_field_outcomes do |t|
      t.references :extraction_attempt, null: false, index: false,
                   foreign_key: { on_delete: :cascade }
      t.integer :candidate_index, null: false
      t.string :field, null: false
      t.string :outcome, null: false
      t.text :proposed
      t.text :accepted

      t.timestamps
    end

    add_index :extraction_field_outcomes, %i[extraction_attempt_id candidate_index field], unique: true
    add_index :extraction_field_outcomes, %i[field outcome]
  end
end
