namespace :taxonomy do
  desc "Generate a draft genre tree (db/genres.yml) from the current flat " \
       "Style→Genre seed. A starting point to cultivate by hand, not a finished seed."
  task draft_tree: :environment do
    require "json"
    require "yaml"

    root = File.expand_path("../..", __dir__)
    taxonomy     = JSON.parse(File.read(File.join(root, "lib/genres.json")))
    aliases      = JSON.parse(File.read(File.join(root, "lib/genre_aliases.json")))
    dispositions = JSON.parse(File.read(File.join(root, "lib/genre_dispositions.json")))

    disposed = dispositions.values.flatten.map { |n| Genre.fingerprint_for(n) }.to_set
    aliased  = aliases.values.flatten.map { |n| Genre.fingerprint_for(n) }.to_set
    excluded = disposed | aliased

    roots = taxonomy.map do |style_name, genre_names|
      style_fp = Genre.fingerprint_for(style_name)
      children = genre_names
                 .reject { |n| excluded.include?(Genre.fingerprint_for(n)) || Genre.fingerprint_for(n) == style_fp }
                 .uniq { |n| Genre.fingerprint_for(n) }
                 .sort
      { "name" => style_name, "children" => children }
    end

    tree = {
      "genres"  => roots,
      "hidden"  => Array(dispositions["hidden"]).sort,
      "blocked" => Array(dispositions["blocked"]).sort,
      "ignored" => Array(dispositions["ignored"]).sort,
      "aliases" => aliases
    }

    out = File.join(root, "db/genres.yml")
    header = <<~YAML
      # Curated genre tree — the backbone seed loaded by `rake taxonomy:import_tree`.
      #
      # GENERATED DRAFT (rake taxonomy:draft_tree). Cultivate by hand: nest children
      # under intermediate parents (e.g. Rock > Punk > Crustpunk), prune contaminants,
      # rename roots. Re-running draft_tree OVERWRITES this file, so edit in place and
      # don't regenerate once you've started cultivating.
      #
      #   genres:  nested name/children tree (roots = top-level genres, no parent)
      #   hidden:  non-music genres (event hidden iff it has only hidden genres)
      #   blocked: scraper noise, never a real genre (tag stripped on sight)
      #   ignored: real, publicly-shown genres deliberately left unplaced
      #   aliases: canonical => [spelling variants] the fingerprint can't catch
    YAML
    File.write(out, header + tree.to_yaml.sub(/\A---\n/, ""))

    child_count = roots.sum { |r| r["children"].size }
    puts "Wrote #{out}"
    puts "  #{roots.size} roots, #{child_count} children, " \
         "#{tree['hidden'].size} hidden, #{tree['blocked'].size} blocked, " \
         "#{tree['ignored'].size} ignored, #{aliases.size} alias groups"
  end

  desc "Load the curated genre tree (db/genres.yml): upsert genres, set parents " \
       "from the nesting, apply dispositions + aliases. Idempotent."
  task import_tree: :environment do
    require "yaml"
    path = ENV["GENRES_TREE"].presence || Rails.root.join("db/genres.yml")
    result = GenreTreeSeed.import(YAML.load_file(path))

    puts "Loaded genre tree from #{path}: #{result.placed} placed under a parent, " \
         "#{result.tree_entries} tree entries, #{result.hidden} hidden, " \
         "#{result.blocked} blocked, #{result.ignored} ignored, #{result.alias_groups} alias groups"
    if result.multi_home.any?
      warn "  ⚠ #{result.multi_home.size} genre(s) listed under multiple parents (last wins, " \
           "tree is single-parent) — resolve in db/genres.yml."
    end
  end

  desc "Reset the genre taxonomy: wipe the tree rows, reload db/genres.yml, and " \
       "recompute every event's visibility. Run once in prod after deploy."
  task reset: :environment do
    removed = Genre.count
    Genre.delete_all
    Rake::Task["taxonomy:import_tree"].execute
    Event.find_each(&:recompute_visibility!)
    puts "taxonomy:reset — cleared #{removed} genre rows, reloaded the tree, " \
         "recomputed visibility for #{Event.count} events."
  end
end
