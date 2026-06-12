class AddCreatedInScrapeRunToEvents < ActiveRecord::Migration[8.0]
  def change
    # The run that first created this event. Nullify (not cascade) on delete so
    # pruning old runs never removes the events they introduced — they just lose
    # the backlink.
    add_reference :events, :created_in_scrape_run,
                  foreign_key: { to_table: :scrape_runs, on_delete: :nullify },
                  null: true
  end
end
