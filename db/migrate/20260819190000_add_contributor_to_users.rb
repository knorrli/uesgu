class AddContributorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :contributor, :boolean, default: false, null: false
  end
end
