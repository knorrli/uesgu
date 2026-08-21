module EventCapture
  # The genre names the taxonomy already carries, asked the one question a captured
  # genre raises: is this a name we know?
  #
  # It exists for the slash run — a poster printing "Loops/Groove/FX/Electronic/Jazz/Dub"
  # comes back from the model as ONE genre. A blind split is not available: a genre
  # name can carry a slash itself, and splitting such a name mints two genres that do
  # not exist. So the taxonomy decides — a run splits where it vouches for a part, and
  # stays whole where it vouches for the whole.
  class Genres
    SEPARATOR = "/".freeze

    # Blocked genres vouch for nothing — scraper noise, never a real name. Everything
    # else counts, aliases and dormant seed rows included: recognising
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
