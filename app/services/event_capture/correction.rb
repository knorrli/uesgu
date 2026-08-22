module EventCapture
  # What a contributor reports about a read they are sending back: which fields the
  # model got wrong, and what they say the input actually shows.
  #
  # The report is the mechanism, not decoration. Infomaniak#request_body sets no
  # `temperature`, so the model may be sampling deterministically — in which case an
  # identical request returns the identical wrong answer and the button looks broken.
  # Nobody here knows the provider's default and it is not ours to rely on. A report
  # changes the PROMPT, so the second read differs wherever that dial sits.
  #
  # It never enters Prompt.sha. A sentence one contributor typed is request data, not
  # a prompt edit: hashing it would mint a fresh sha per re-read and the column would
  # measure contributors instead of the wording it exists to attribute numbers to.
  class Correction < Data.define(:fields, :note)
    # The model's own field names, because the block below is read BY the model.
    # `canton` is absent because code computes it from the locality and no re-read can
    # move it; `source_url` because the card never renders it — it only feeds
    # PlaceSuggester's registry match, so nobody sees a link to call wrong.
    FIELDS = %w[title date time place locality genres].freeze
    NOTE_LIMIT = 200

    def self.from(fields:, note:)
      new(fields: FIELDS & fields.to_s.split(",").map { |field| field.strip.downcase },
          note: note.to_s.squish.truncate(NOTE_LIMIT).presence)
    end

    def initialize(fields: [], note: nil) = super

    def to_prompt
      <<~TXT
        THIS IS A SECOND READ OF AN INPUT YOU HAVE ALREADY BEEN GIVEN ONCE.

        A person compared your last answer against the input and is asking again.
        #{marked}#{reported}
        Read the input again. Every rule above still stands, the evidence rule above
        all: a value you cannot quote is null however plainly the report contradicts
        you. The report tells you where to look. It is never itself a value — a field
        is filled from the input or it is filled from nothing.
      TXT
    end

    private

    def marked
      return "Nothing was marked wrong; you are being asked for a plain second look.\n" if fields.empty?

      "These fields are wrong: #{fields.map { |field| "`#{field}`" }.join(', ')}.\n"
    end

    # Fenced and squished into one line by `from` above: this is a contributor's own
    # words riding in the SYSTEM message, where anything laid out like a rule reads
    # like one. The fence is not a boundary — nothing stops a note writing a fence of
    # its own — and the human who reads every field on the capture screen before
    # publishing is, as with a pasted input, the actual check.
    def reported
      return "" if note.blank?

      "What they say the input shows: <<<REPORT\n#{note}\nREPORT\n"
    end
  end
end
