class AddGenreBlock < ActiveRecord::Migration[8.0]
  def change
    # A genre marked "blocked" is scraper noise that was never a real descriptor
    # (e.g. Docks country codes Us/Au/Ch, Mahogany Hall artist-name fragments). A
    # fourth disposition alongside mapped-to-style, ignored and hidden: unlike
    # those it strips the genre from ingestion entirely, so it never appears as a
    # tag — re-applied every scrape since scrapers re-tag by name (see Event#genre_list=).
    add_column :genres, :blocked_at, :datetime
    add_index :genres, :blocked_at
  end
end
