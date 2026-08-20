class CreateExtractionAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :extraction_attempts do |t|
      t.string :status, null: false
      t.string :code
      t.string :medium
      t.string :model
      t.string :prompt_sha
      t.integer :candidates_count, default: 0, null: false
      t.integer :input_tokens, default: 0, null: false
      t.integer :output_tokens, default: 0, null: false
      t.integer :duration_ms
      t.jsonb :issues, default: {}, null: false
      t.text :error_message

      t.timestamps
    end

    add_index :extraction_attempts, :created_at
    add_index :extraction_attempts, %i[model prompt_sha]
  end
end
