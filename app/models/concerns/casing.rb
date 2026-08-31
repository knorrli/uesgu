# Recovers the casing of text a source printed in capitals: posters are set in caps,
# and several venue sites shout their whole programme.
#
# Only a string shouted as a WHOLE is touched. A capitalised word among mixed-case
# neighbours ("LEYA + Junge Eko") is a decision somebody made about a name, because
# nothing upper-cased the rest of the line — so any lowercase anywhere leaves the
# string alone, and the evidence costs nothing to read. A lone word is left alone at
# the other end: that is where deliberate stylings sit (KMFDM, ECHT!), and nothing
# inside the string tells one apart from a shouted ordinary word.
#
# Title case rather than sentence case because these strings are mostly proper
# names — sentence case turns "DEINE COUSINE" into "Deine cousine".
module Casing
  # Kept in caps where an ordinary parenthesised phrase is not: venue programmes
  # append the act's country, and "(De)" reads as a word.
  COUNTRY_CODE = %r{\(\p{Upper}{2,4}(?:/\p{Upper}{2,4})*\)}

  # Abbreviations of the domain, kept in their conventional spelling rather than
  # title-cased. Matched on the WHOLE token, so "DJANGO" is untouched.
  #
  # Deliberately holds no artist names. Those are rulings about one entity, an admin
  # edit makes them stick per event, and a list that accepted them would grow with the
  # corpus for ever. Country codes that double as ordinary words stay out for a
  # different reason: "US" and "IN" are a pronoun and a preposition far more often than
  # they are countries, and the parenthesised form is already kept above.
  ABBREVIATIONS = { "dj" => "DJ", "djs" => "DJs", "mc" => "MC", "mcs" => "MCs",
                    "ep" => "EP", "lp" => "LP", "uk" => "UK", "usa" => "USA" }.freeze

  # A single letter is not a word. Counting them would read "SUNN O)))" as two and
  # recase a name.
  WORD = /\p{Alpha}{2,}/

  # The apostrophe rides INSIDE the word so that String#capitalize lowercases what
  # follows it: "OTTO'S" -> "Otto's", not "Otto'S". A letter run led by a digit is a
  # suffix rather than a word of its own — "2000ER" is "2000er", not "2000Er".
  TITLE_WORD = /(?<digit>\d)?(?<word>\p{Alpha}+(?:['’]\p{Alpha}+)*)/

  def self.shouted?(str)
    str = str.to_s
    str.match?(/\p{Upper}/) && !str.match?(/\p{Lower}/)
  end

  def self.recasable?(str) = shouted?(str) && str.to_s.scan(WORD).size > 1

  # Returns the string untouched when the rule does not fire, so a caller can pass
  # every value through without asking first.
  def self.recase(str)
    return str unless recasable?(str)

    str.split(/(#{COUNTRY_CODE})/).each_with_index
       .map { |part, index| index.odd? ? part : titlecased(part) }
       .join
  end

  def self.titlecased(str)
    str.gsub(TITLE_WORD) do
      digit, word = Regexp.last_match(:digit), Regexp.last_match(:word)
      next "#{digit}#{word.downcase}" if digit

      ABBREVIATIONS[word.downcase] || word.capitalize
    end
  end
end
