module GenresHelper
  MAX_INDENT_DEPTH = 4

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

  def genre_tree_option(genre, depth, descendant_count)
    parts = [tag.span(genre.name, class: class_names("genre-option-name", umbrella: descendant_count.positive?))]
    parts << tag.span(descendant_count, class: "genre-option-count") if descendant_count.positive?
    content = tag.span(safe_join(parts), class: "genre-tree-option",
                       data: { depth: [depth, MAX_INDENT_DEPTH].min })
    { display: genre.name, value: genre.id, content: content }
  end

  def genre_combobox_options(genres, counts: Genre.descendant_counts)
    genres.to_a.sort_by { |genre| [-counts[genre.id], genre.name.downcase] }.map do |genre|
      main = [tag.span(genre.name, class: "genre-option-name")]
      path = genre_ancestor_label(genre)
      main << tag.span("· #{path}", class: "genre-option-path") if path.present?
      parts = [tag.span(safe_join(main), class: "genre-option-main")]
      parts << tag.span(counts[genre.id], class: "genre-option-count") if counts[genre.id].positive?
      { display: genre.name, value: genre.name, content: safe_join(parts) }
    end
  end

  def genre_ancestor_label(genre)
    (@genre_ancestor_paths ||= Genre.ancestor_paths)[genre.id].to_a.join(" › ")
  end
end
