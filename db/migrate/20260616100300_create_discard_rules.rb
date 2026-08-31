class CreateDiscardRules < ActiveRecord::Migration[8.0]
  def change
    create_table :discard_rules do |t|
      t.string :pattern, null: false
      t.string :scraper
      t.boolean :active, null: false, default: true
      t.string :note

      t.timestamps
    end
  end
end
