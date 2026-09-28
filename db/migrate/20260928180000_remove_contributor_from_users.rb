class RemoveContributorFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :contributor, :boolean, default: false, null: false
  end
end
