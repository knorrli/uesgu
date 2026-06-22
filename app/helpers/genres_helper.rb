module GenresHelper
  # Build hotwire_combobox options for a set of genres, each shown as its name
  # plus a right-aligned descendant count for the umbrella genres (those with
  # sub-genres). Umbrellas sort to the top, so the broad buckets you reach for
  # most (Rock, Electronic …) lead the list instead of being scattered
  # alphabetically; the count is render-only, so typing still filters on the name.
  # Shared by the genre editor's "set parent" picker and the admin event editor's
  # genre assignment, so both surface the tree's umbrellas the same way.
  def genre_combobox_options(genres, counts: Genre.descendant_counts)
    genres.to_a
          .sort_by { |genre| [-counts[genre.id], genre.name.downcase] }
          .map do |genre|
            count = counts[genre.id]
            name = tag.span(genre.name)
            content = count.positive? ? safe_join([name, tag.span(count, class: 'genre-option-count')]) : name
            { display: genre.name, value: genre.id, content: content }
          end
  end
end
