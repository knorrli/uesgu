module EventCapture
  # The curated locality name variants no string measure reaches. Freiburg IS
  # Fribourg and Genf IS Genève, but the pairs share almost no trigrams (0.29 and
  # 0.33), and there is no threshold that admits them while excluding unrelated
  # towns — so they are a PR-reviewed list in config/locality_aliases.yml rather
  # than arithmetic.
  #
  # A match is a LINK, never a rewrite: like genre aliases (see Genre#canonical_id)
  # this resolves at entry and leaves stored data alone. An event already published
  # under "Bienne" keeps that tag.
  class LocalityAliases
    CONFIG_PATH = Rails.root.join("config/locality_aliases.yml")

    class << self
      # Memoized like the venue registry, and cleared the same way it is: the class is
      # redefined on code reload in dev, so editing the YAML means a restart.
      def curated = @curated ||= new(YAML.safe_load_file(CONFIG_PATH).fetch("localities"))

      def reload! = (@curated = nil)

      def none = new({})
    end

    attr_reader :canonicals

    def initialize(canonicals)
      @canonicals = canonicals
      @by_key = canonicals.flat_map { |name, variants|
        Array(variants).map { |variant| [Fingerprint.for(variant), name] }
      }.to_h
    end

    def canonical_for(typed)
      return if typed.blank?

      by_key[Fingerprint.for(typed)]
    end

    private

    attr_reader :by_key
  end
end
