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
       'map its listed genres to it (matched/de-duplicated by fingerprint). The ' \
       'clean-slate seed for a fresh database. Safe to re-run (idempotent).'
  task import_taxonomy: :environment do
    taxonomy = JSON.parse(File.read(Rails.root.join('lib/genres.json')))

    taxonomy.each do |style_name, genre_names|
      style = Style.find_or_create_by!(name: style_name)
      Genre.ensure!(genre_names)
      fingerprints = genre_names.map { |name| Genre.fingerprint_for(name) }.uniq
      genres = Genre.where(fingerprint: fingerprints)
      style.genre_ids = (style.genre_ids + genres.ids).uniq
    end

    Genre.reconcile!
    puts "Imported #{taxonomy.size} styles, #{Genre.count} genres total"
  end

  desc 'Merge known semantic aliases (lib/genre_aliases.json) into their ' \
       'canonical genres. Mechanical spelling variants are handled by the ' \
       'fingerprint and need no entry here. Idempotent.'
  task import_aliases: :environment do
    aliases = JSON.parse(File.read(Rails.root.join('lib/genre_aliases.json')))
    merged = 0
    aliases.each do |canonical_name, alias_names|
      Genre.ensure!([canonical_name, *alias_names])
      canonical = Genre.find_by(fingerprint: Genre.fingerprint_for(canonical_name))
      Array(alias_names).each do |alias_name|
        genre = Genre.find_by(fingerprint: Genre.fingerprint_for(alias_name))
        next unless genre && canonical && genre.id != canonical.id

        genre.merge_into!(canonical)
        merged += 1
      end
    end
    puts "Merged #{merged} aliases"
  end

  desc 'Pre-seed dispositions (lib/genre_dispositions.json): block scraper noise, ' \
       'hide non-music events, ignore visible-but-unmapped tags. Idempotent.'
  task import_dispositions: :environment do
    dispositions = JSON.parse(File.read(Rails.root.join('lib/genre_dispositions.json')))
    Genre.ensure!(dispositions.values.flatten)
    { 'blocked' => :block!, 'hidden' => :hide!, 'ignored' => :ignore! }.each do |key, method|
      Array(dispositions[key]).each do |name|
        Genre.find_by(fingerprint: Genre.fingerprint_for(name))&.public_send(method)
      end
    end
    puts "Applied dispositions: #{dispositions.transform_values(&:size)}"
  end

  desc 'Seed the full genre taxonomy, aliases, and dispositions in order. The ' \
       'one-shot seed for a fresh database. Idempotent.'
  task seed: :environment do
    Rake::Task['genres:import_taxonomy'].invoke
    Rake::Task['genres:import_aliases'].invoke
    Rake::Task['genres:import_dispositions'].invoke
    Genre.reconcile!
    puts 'Genre seed complete.'
  end
end
