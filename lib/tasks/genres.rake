namespace :genres do
  desc 'Backfill the first-class genre → style mapping from the previous ' \
       "representation (a Style 'tagged with' genre strings via " \
       'acts_as_taggable_on), register every genre currently on an event, and ' \
       "recompute each event's derived styles. Safe to re-run (idempotent); the " \
       'one-time step after introducing the Genre model.'
  task backfill: :environment do
    # Current mappings: genre name → the style ids it maps to.
    mapping = Hash.new { |hash, name| hash[name] = [] }
    ActsAsTaggableOn::Tagging
      .where(context: 'genres', taggable_type: 'Style')
      .joins(:tag)
      .pluck('tags.name', :taggable_id)
      .each { |name, style_id| mapping[name] << style_id }

    mapping.each do |name, style_ids|
      genre = Genre.create_or_find_by!(name: name)
      genre.style_ids = style_ids.uniq
    end
    puts "Genre mappings backfilled: #{mapping.size}"

    # Register every genre currently on an event (unmapped ones become the
    # assignment queue) and cache usage counts.
    Genre.reconcile!
    puts "Genres in use: #{Genre.in_use.count} (#{Genre.unassigned.count} unassigned)"

    # Re-derive every event's styles from the new mapping. Should reproduce the
    # existing style tags exactly.
    events_changed = 0
    Event.find_each do |event|
      before = event.style_list.sort
      event.recompute_styles!
      events_changed += 1 if event.reload.style_list.sort != before
    end
    puts "Events whose styles changed on recompute: #{events_changed}"
  end

  desc 'Import the style taxonomy from lib/genres.json: create each Style and ' \
       'map its listed genres to it. The clean-slate seed for a fresh database ' \
       '(replaces the old ReloadStylesJob). Safe to re-run (idempotent).'
  task import_taxonomy: :environment do
    taxonomy = JSON.parse(File.read(Rails.root.join('lib/genres.json')))

    taxonomy.each do |style_name, genre_names|
      style = Style.find_or_create_by!(name: style_name)
      Genre.ensure!(genre_names)
      genres = Genre.where('lower(name) IN (?)', genre_names.map(&:downcase).presence || [nil])
      style.genre_ids = (style.genre_ids + genres.ids).uniq
    end

    # Refresh usage counts (genres carry no events yet on a fresh database).
    Genre.reconcile!
    puts "Imported #{taxonomy.size} styles, #{Genre.count} genres total"
  end
end
