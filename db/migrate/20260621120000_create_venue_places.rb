class CreateVenuePlaces < ActiveRecord::Migration[8.0]
  def change
    # Structured [venue, city, canton] places resolved per-event by a multi-venue
    # aggregator (e.g. Bewegungsmelder OLE). Single-venue scrapers declare their
    # place in code, so Location derives the taxonomy from them; a per-event
    # aggregator can't, and AATO flattens the tuple into three unordered tags on
    # the event — losing which is the venue vs the city. We persist the tuple here
    # at scrape time so Location can fold these venues into the WHERE hierarchy and
    # classify them correctly. Upserted by source key, idempotent across sweeps.
    create_table :venue_places do |t|
      t.string :venue,  null: false
      t.string :city
      t.string :canton
      t.string :source, null: false # the aggregator's provenance, e.g. "OLE:Bewegungsmelder"
      t.timestamps
    end
    add_index :venue_places, %i[venue city canton], unique: true
  end
end
