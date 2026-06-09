class AddGenreExclusion < ActiveRecord::Migration[8.0]
  def change
    # A genre marked "not music" (e.g. Lesung, Theater, Public-Viewing): a third
    # disposition alongside mapped-to-style and dismissed.
    add_column :genres, :excluded_at, :datetime
    add_index :genres, :excluded_at

    # Derived: an event is hidden from public listings when it carries an
    # excluded genre and has no music style (see Event#recompute_styles!).
    add_column :events, :hidden, :boolean, default: false, null: false
    add_index :events, :hidden
  end
end
