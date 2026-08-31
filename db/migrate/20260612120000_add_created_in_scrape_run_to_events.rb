class AddCreatedInScrapeRunToEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :events, :created_in_scrape_run,
                  foreign_key: { to_table: :scrape_runs, on_delete: :nullify },
                  null: true
  end
end
