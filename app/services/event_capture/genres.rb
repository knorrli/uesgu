module EventCapture
  class Genres
    SEPARATORS = %r{[/·|]}

    def self.known = new(Genre.where(blocked_at: nil).pluck(:fingerprint))

    def self.for_names(names) = new(names.map { |name| Fingerprint.for(name) })

    def self.none = new([])

    def initialize(keys)
      @keys = keys.filter_map(&:presence).to_set
    end

    def split(name)
      parts = name.to_s.split(SEPARATORS).filter_map { |part| part.strip.presence }
      return [name] if parts.size < 2 || whole?(name, parts)

      parts.any? { |part| known?(part) } ? parts : [name]
    end

    private

    attr_reader :keys

    def whole?(name, parts) = known?(name) || known?(parts.join(" & "))

    def known?(name) = keys.include?(Fingerprint.for(name))
  end
end
