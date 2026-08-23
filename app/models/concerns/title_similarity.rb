# Whether two event titles name the same show. One implementation for both places
# that ask: the nightly auto-merge (Scrapers::Dedup) and the match a capture card
# offers a contributor (EventCapture::DuplicateFinder). A second tokenizer would let
# the two disagree about what "the same show" is, and the card would then propose a
# merge the next sweep undoes.
#
# Titles are compared as token SETS, not as strings: sources word the same gig
# differently ("Malevolence" vs "Malevolence (UK) + support"), so order and
# punctuation carry nothing. What is left after the stopwords is the lineup.
module TitleSimilarity
  # Jaccard overlap at or above which two titles are the same show. Low because the
  # comparison is only ever reached by rows already sharing a venue and a date, so
  # the remaining question is narrow.
  THRESHOLD = 0.4

  # Words that say nothing about WHICH show this is: articles across the three
  # languages, the billing vocabulary every lineup repeats, and the country codes a
  # listing hangs off an artist name.
  STOP = %w[the a le la les der die das und and feat featuring with vs b2b support
            live concert show tour ch us uk fr de present presents].freeze

  module_function

  def tokens(title)
    title.to_s.downcase
         .tr("äöüàâéèêëïîçáí", "aouaaeeeeiicai")
         .gsub(/\(.*?\)/, " ")
         .gsub(/[^a-z0-9 ]/, " ")
         .split
         .reject { |t| STOP.include?(t) || t.length < 2 }
         .to_set
  end

  def jaccard(a, b)
    return 0.0 if a.empty? || b.empty?

    (a & b).size.to_f / (a | b).size
  end

  # One title's words wholly contained in the other's is a match on its own, at any
  # overlap: our club scrapers truncate "Darkside" where the feed lists the full DJ
  # lineup, and no threshold catches that pair without also joining unrelated ones.
  def subset?(a, b)
    !a.empty? && !b.empty? && (a.subset?(b) || b.subset?(a))
  end

  def match?(a, b) = subset?(a, b) || jaccard(a, b) >= THRESHOLD
end
