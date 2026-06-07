class AddLocaleToUsers < ActiveRecord::Migration[8.0]
  def change
    # Nullable: no preference means "follow the browser".
    add_column :users, :locale, :string
  end
end
