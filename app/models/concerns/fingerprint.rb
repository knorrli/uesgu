module Fingerprint
  ACCENTS_FROM = "äöüàâéèêëïîôûç".freeze
  ACCENTS_TO   = "aouaaeeeeiiouc".freeze

  def self.for(str)
    str.to_s.downcase
       .gsub("&", "and").gsub("'n'", "and")
       .tr(ACCENTS_FROM, ACCENTS_TO)
       .gsub(/[^a-z0-9]/, "")
  end

  def self.folded(str)
    str.to_s.downcase
       .gsub("&", "and").gsub("'n'", "and")
       .tr(ACCENTS_FROM, ACCENTS_TO)
       .gsub(/[^a-z0-9]+/, " ")
       .strip
  end
end
