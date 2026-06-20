namespace :genres do
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

  desc 'Seed the full genre taxonomy from the curated tree (db/genres.yml): the ' \
       'one-shot seed for a fresh database. Loads the tree (which also applies its ' \
       'own dispositions + aliases), then reconciles usage counts. Idempotent.'
  task seed: :environment do
    # The curated tree (taxonomy:import_tree / GenreTreeSeed) is the single source
    # of truth now — it sets parents AND applies the hidden/blocked/ignored
    # dispositions and aliases from the YAML, replacing the old flat Style→Genre
    # import. execute (not invoke) so a re-run never silently no-ops.
    Rake::Task['taxonomy:import_tree'].execute
    Genre.reconcile!
    puts 'Genre seed complete.'
  end
end
