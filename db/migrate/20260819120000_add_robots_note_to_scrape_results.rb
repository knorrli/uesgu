class AddRobotsNoteToScrapeResults < ActiveRecord::Migration[8.1]
  def change
    add_column :scrape_results, :robots_note, :text
  end
end
