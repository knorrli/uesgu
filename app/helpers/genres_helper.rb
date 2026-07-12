module GenresHelper
  # How deep the picker keeps indenting a nested genre before it stops adding
  # inset (deeper levels share the last step). The taxonomy is shallow; this is a
  # guard against a runaway chain pushing an option off the right edge.
  MAX_INDENT_DEPTH = 4

  # Build hotwire_combobox options that render the genre TREE: every candidate at
  # its true depth, indented (via a data-depth hook styled in genres.css) with its
  # descendants nested beneath it depth-first, so the hierarchy reads at a glance
  # instead of a flat alphabetical wall. Cultivated umbrellas (genres with
  # sub-genres) lead — broadest first — and the loose, not-yet-filed genres trail
  # at the bottom. `genres` is the already-filtered candidate set (the caller
  # excludes self/descendants and disposed genres); only those are offered, but
  # indentation reflects each one's real place in the whole tree. `display` stays
  # the bare name, so typing still filters on the name. Powers the editor's "set
  # parent" and "merge" pickers.
  def genre_tree_options(genres)
    offered = genres.index_by(&:id)
    name_of = {}
    parent_of = {}
    children = Hash.new { |hash, key| hash[key] = [] }
    Genre.pluck(:id, :parent_id, :name).each do |id, parent_id, name|
      name_of[id] = name
      parent_of[id] = parent_id
      children[parent_id] << id
    end

    counts = Genre.descendant_counts
    depth_of = {}
    depth = lambda { |id| depth_of[id] ||= (pid = parent_of[id]) ? depth.call(pid) + 1 : 0 }

    # Umbrellas (most sub-genres) first among siblings, then A–Z; recurse
    # depth-first so each subtree stays contiguous under its root and the loose
    # count-0 genres fall to the bottom.
    sort = ->(ids) { ids.sort_by { |id| [-counts[id], name_of[id].to_s.downcase] } }
    ordered = []
    walk = lambda do |id|
      ordered << id
      sort.call(children[id]).each { |child| walk.call(child) }
    end
    sort.call(children[nil]).each { |id| walk.call(id) }

    ordered.filter_map do |id|
      genre = offered[id]
      genre_tree_option(genre, depth.call(id), counts[id]) if genre
    end
  end

  # One tree-picker option: the name (bold when it's an umbrella) at its indent
  # depth, with a right-aligned descendant count for the umbrellas. The count is
  # render-only, so typing still filters on the name.
  def genre_tree_option(genre, depth, descendant_count)
    parts = [tag.span(genre.name, class: class_names("genre-option-name", umbrella: descendant_count.positive?))]
    parts << tag.span(descendant_count, class: "genre-option-count") if descendant_count.positive?
    content = tag.span(safe_join(parts), class: "genre-tree-option",
                       data: { depth: [depth, MAX_INDENT_DEPTH].min })
    { display: genre.name, value: genre.id, content: content }
  end

  # Build hotwire_combobox options for a set of genres, each shown as its name
  # plus a right-aligned descendant count for the umbrella genres (those with
  # sub-genres). Umbrellas sort to the top, so the broad buckets you reach for
  # most (Rock, Electronic …) lead the list instead of being scattered
  # alphabetically; the count is render-only, so typing still filters on the name.
  # Shared by the genre editor's "set parent" picker and the admin event editor's
  # genre assignment, so both surface the tree's umbrellas the same way.
  def genre_combobox_options(genres, counts: Genre.descendant_counts, preserve_order: false)
    list = genres.to_a
    list = list.sort_by { |genre| [-counts[genre.id], genre.name.downcase] } unless preserve_order
    list.map do |genre|
      # name [· ancestor › path] .......... descendant-count. The path shows where
      # a candidate sits so you can tell a precise child ("Grind · Metal") from a
      # broad root; both are render-only, so typing still filters on the name.
      main = [tag.span(genre.name, class: "genre-option-name")]
      path = genre_ancestor_label(genre)
      main << tag.span("· #{path}", class: "genre-option-path") if path.present?
      parts = [tag.span(safe_join(main), class: "genre-option-main")]
      parts << tag.span(counts[genre.id], class: "genre-option-count") if counts[genre.id].positive?
      { display: genre.name, value: genre.id, content: safe_join(parts) }
    end
  end

  # "Metal › Grind" — the tree path from the root down to this genre's parent
  # (blank for a root). Memoizes the whole-taxonomy path map for the request, so
  # annotating a full picker + the related-genre rows is one query, not one per
  # row.
  def genre_ancestor_label(genre)
    (@genre_ancestor_paths ||= Genre.ancestor_paths)[genre.id].to_a.join(" › ")
  end
end
