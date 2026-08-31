module TitleSimilarity
  THRESHOLD = 0.4

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

  def subset?(a, b)
    !a.empty? && !b.empty? && (a.subset?(b) || b.subset?(a))
  end

  def match?(a, b) = subset?(a, b) || jaccard(a, b) >= THRESHOLD
end
