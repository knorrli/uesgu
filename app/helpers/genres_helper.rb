module GenresHelper
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
