namespace :taxonomy do
  # ---------------------------------------------------------------------------
  # Phase 0 — draft tree seed (tooling, no app change).
  #
  # Generate a *draft* genre tree (db/genres.yml) from today's flat taxonomy:
  # each Style becomes a root genre, the genres mapped to it become its children,
  # and the existing aliases/dispositions are carried over verbatim. The output is
  # a first draft to cultivate BY HAND (deepen the tree, prune contaminants), not
  # a finished seed — it just means cultivation starts from something real rather
  # than a blank page. Reads the source-of-truth seed JSON (lib/genres.json et al)
  # and folds names with Genre.fingerprint_for (the single matching key, so the
  # draft dedupes exactly as the loader will). See docs/taxonomy-and-saved-filters-redesign.md.
  # ---------------------------------------------------------------------------
  desc 'Generate a draft genre tree (db/genres.yml) from the current flat ' \
       'Style→Genre seed. A starting point to cultivate by hand, not a finished seed.'
  task draft_tree: :environment do
    require 'json'
    require 'yaml'

    root = File.expand_path('../..', __dir__)
    taxonomy     = JSON.parse(File.read(File.join(root, 'lib/genres.json')))
    aliases      = JSON.parse(File.read(File.join(root, 'lib/genre_aliases.json')))
    dispositions = JSON.parse(File.read(File.join(root, 'lib/genre_dispositions.json')))

    # Names already spoken for as a disposition or an alias must not also appear
    # as tree children — a placed genre carries no disposition (see Genre#set_parent!).
    disposed = dispositions.values.flatten.map { |n| Genre.fingerprint_for(n) }.to_set
    aliased  = aliases.values.flatten.map { |n| Genre.fingerprint_for(n) }.to_set
    excluded = disposed | aliased

    roots = taxonomy.map do |style_name, genre_names|
      # Drop children that fingerprint-collapse onto their own root name (e.g.
      # "pop" under root "Pop") — they ARE the root, not a child of it.
      style_fp = Genre.fingerprint_for(style_name)
      children = genre_names
                 .reject { |n| excluded.include?(Genre.fingerprint_for(n)) || Genre.fingerprint_for(n) == style_fp }
                 .uniq { |n| Genre.fingerprint_for(n) }
                 .sort
      { 'name' => style_name, 'children' => children }
    end

    tree = {
      'genres'  => roots,
      'hidden'  => Array(dispositions['hidden']).sort,
      'blocked' => Array(dispositions['blocked']).sort,
      'ignored' => Array(dispositions['ignored']).sort,
      'aliases' => aliases
    }

    out = File.join(root, 'db/genres.yml')
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
    File.write(out, header + tree.to_yaml.sub(/\A---\n/, ''))

    child_count = roots.sum { |r| r['children'].size }
    puts "Wrote #{out}"
    puts "  #{roots.size} roots, #{child_count} children, " \
         "#{tree['hidden'].size} hidden, #{tree['blocked'].size} blocked, " \
         "#{tree['ignored'].size} ignored, #{aliases.size} alias groups"
  end

  # ---------------------------------------------------------------------------
  # Phase 1 — tree seed loader.
  #
  # Load the cultivated genre tree (db/genres.yml) into the database: upsert a
  # Genre per name (matched/deduped by fingerprint, reusing Genre.ensure!), set
  # each genre's parent from the YAML nesting, and apply the hidden/blocked/
  # ignored dispositions and aliases. Idempotent — re-running converges (safe on
  # every deploy or by hand). Genres NOT in the seed (e.g. new scrapes) are left
  # untouched, so they stay unplaced in the admin curation queue. The seed is the
  # curated backbone; scrapers add leaves you then file.
  # ---------------------------------------------------------------------------
  desc 'Load the curated genre tree (db/genres.yml): upsert genres, set parents ' \
       'from the nesting, apply dispositions + aliases. Idempotent.'
  task import_tree: :environment do
    require 'yaml'
    path = ENV['GENRES_TREE'].presence || Rails.root.join('db/genres.yml')
    result = GenreTreeSeed.import(YAML.load_file(path))

    puts "Loaded genre tree from #{path}: #{result.placed} placed under a parent, " \
         "#{result.tree_entries} tree entries, #{result.hidden} hidden, " \
         "#{result.blocked} blocked, #{result.ignored} ignored, #{result.alias_groups} alias groups"
    if result.multi_home.any?
      warn "  ⚠ #{result.multi_home.size} genre(s) listed under multiple parents (last wins, " \
           'tree is single-parent) — resolve in db/genres.yml.'
    end
  end
end
