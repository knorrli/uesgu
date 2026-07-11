namespace :genres do
  desc "Merge known semantic aliases (lib/genre_aliases.json) into their " \
       "canonical genres. Mechanical spelling variants are handled by the " \
       "fingerprint and need no entry here. Idempotent."
  task import_aliases: :environment do
    aliases = JSON.parse(File.read(Rails.root.join("lib/genre_aliases.json")))
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

  desc "Pre-seed dispositions (lib/genre_dispositions.json): block scraper noise, " \
       "hide non-music events, ignore visible-but-unmapped tags. Idempotent."
  task import_dispositions: :environment do
    dispositions = JSON.parse(File.read(Rails.root.join("lib/genre_dispositions.json")))
    Genre.ensure!(dispositions.values.flatten)
    { "blocked" => :block!, "hidden" => :hide!, "ignored" => :ignore! }.each do |key, method|
      Array(dispositions[key]).each do |name|
        Genre.find_by(fingerprint: Genre.fingerprint_for(name))&.public_send(method)
      end
    end
    puts "Applied dispositions: #{dispositions.transform_values(&:size)}"
  end

  desc "Backfill: strip the leading/trailing punctuation prose-mining welded onto " \
       "genre names (\"Virtuos.\" -> \"Virtuos\"). Cleans the Genre rows, rewrites " \
       "the matching event taggings so cards show the tidy spelling too, then " \
       "reconciles counts. Fingerprint-preserving, so nothing re-splits. Idempotent."
  task tidy_names: :environment do
    # 1. Clean the Genre rows in place. The fingerprint (a stored generated column)
    #    ignores punctuation, so trimming edge noise never changes it — the unique
    #    index can't collide and no row folds into another. Preserve existing casing
    #    (curated names), only trim the edges.
    renamed = 0
    Genre.find_each do |genre|
      clean = genre.name.strip.gsub(Genre::GENRE_EDGE_NOISE, "")
      next if clean == genre.name || clean.blank?

      genre.update_columns(name: clean)
      renamed += 1
    end

    # 2. Rewrite event taggings. Cards render the raw ActsAsTaggableOn tag, not the
    #    Genre row, so a clean row alone still shows the dot. Re-assigning genre_list
    #    re-runs canonicalize_names, which now resolves each dirty raw token onto its
    #    cleaned row. Only save events whose tags actually change.
    retagged = 0
    Event.find_each do |event|
      current = event.genre_list.to_a
      cleaned = Genre.canonicalize_names(current).reject(&:blank?).uniq
      next if cleaned == current

      event.update!(genre_list: cleaned)
      retagged += 1
    end

    # 3. Sync usage counts (and drop any now-orphaned dirty tag to zero).
    Genre.reconcile!
    puts "Tidied #{renamed} genre names, re-tagged #{retagged} events."
  end

  desc "Seed the full genre taxonomy from the curated tree (db/genres.yml): the " \
       "one-shot seed for a fresh database. Loads the tree (which also applies its " \
       "own dispositions + aliases), then reconciles usage counts. Idempotent."
  task seed: :environment do
    # The curated tree (taxonomy:import_tree / GenreTreeSeed) is the single source
    # of truth now — it sets parents AND applies the hidden/blocked/ignored
    # dispositions and aliases from the YAML, replacing the old flat Style→Genre
    # import. execute (not invoke) so a re-run never silently no-ops.
    Rake::Task["taxonomy:import_tree"].execute
    Genre.reconcile!
    puts "Genre seed complete."
  end
end
