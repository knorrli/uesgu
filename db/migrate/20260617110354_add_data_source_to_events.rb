class AddDataSourceToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :data_source, :string
  end
end
