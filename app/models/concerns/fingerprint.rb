# The normalized matching key shared by the vocabularies that fold spelling
# variants into one row — Genre and Place. Each stores it as a STORED generated
# column; this reproduces that SQL exactly for ingest-time matching on raw
# strings that have no row to read the column off.
#
# The SQL lives in each table's migration (a migration must not depend on app
# code) and a per-table round-trip test locks the two halves together. Changing
# the rule here therefore means a new migration per table, not just an edit.
module Fingerprint
  ACCENTS_FROM = "äöüàâéèêëïîôûç".freeze
  ACCENTS_TO   = "aouaaeeeeiiouc".freeze

  def self.for(str)
    str.to_s.downcase
       .gsub("&", "and").gsub("'n'", "and")
       .tr(ACCENTS_FROM, ACCENTS_TO)
       .gsub(/[^a-z0-9]/, "")
  end
end
