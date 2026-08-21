module EventCapture
  # The genre names the taxonomy already carries, asked the one question a captured
  # genre raises: is this a name we know?
  #
  # It exists for the slash run — a poster printing "Loops/Groove/FX/Electronic/Jazz/Dub"
  # comes back from the model as ONE genre. A blind split on the slash is not
  # available: a genre name can carry one itself, and splitting such a name mints two
  # genres that do not exist. So the taxonomy decides. A run stays whole where it is
  # punctuation away from a name we carry, and splits only where at least one part is
  # one — a slash sitting between a genre name and anything else is a list, and one
  # vouched part is the cheapest evidence of that there is.
  #
  # Nothing is dropped and nothing is respelt here. An unvouched part rides along and
  # is minted at publish exactly as a hand-typed genre is, and the card shows every
  # part as its own chip, so an over-eager split is one tap to undo.
  class Genres
    SEPARATOR = "/".freeze

    # Blocked genres vouch for nothing — they are scraper noise, never a real name.
    # Everything else counts, aliases and dormant seed rows included: recognising
    # "Elektronik" says the run is a list exactly as well as recognising "Electronic".
    def self.known = new(Genre.where(blocked_at: nil).pluck(:name))

    def self.none = new([])

    def initialize(names)
      @keys = names.filter_map { |name| Fingerprint.for(name).presence }.to_set
    end

    def split(name)
      parts = name.to_s.split(SEPARATOR).filter_map { |part| part.strip.presence }
      return [name] if parts.size < 2 || whole?(name, parts)

      parts.any? { |part| known?(part) } ? parts : [name]
    end

    private

    attr_reader :keys

    # A stored name stays whole however the poster punctuated it. The fingerprint
    # discards the slash and reads "&" as "and", so "Drum/Bass" is the key of its own
    # row if it has one — and of "Drum & Bass" if that is the spelling we carry.
    def whole?(name, parts) = known?(name) || known?(parts.join(" & "))

    def known?(name) = keys.include?(Fingerprint.for(name))
  end
end
