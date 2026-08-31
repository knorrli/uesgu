class AllowNullEventUrl < ActiveRecord::Migration[8.1]
  def change
    change_column_null :events, :url, true
  end
end
