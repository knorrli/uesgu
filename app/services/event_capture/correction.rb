module EventCapture
  class Correction < Data.define(:fields, :note)
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

    def reported
      return "" if note.blank?

      "What they say the input shows: <<<REPORT\n#{note}\nREPORT\n"
    end
  end
end
