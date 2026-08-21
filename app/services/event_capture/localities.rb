module EventCapture
  # Every locality the taxonomy already carries, with the canton it sits in. Two
  # questions off one set of rows: which stored spelling a typed locality is, and
  # which canton that puts it in.
  #
  # The canton half is here because a poster prints addresses, never canton codes, so
  # a model asked for one can only infer it and the evidence rule has nothing to
  # police — while these rows already know the answer (see
  # docs/user-event-capture-design.md).
  class Localities
    Entry = Data.define(:name, :canton)

    # Registry first, so its PR-reviewed spelling and canton are the ones that win.
    def self.known
      new(Venue.in_taxonomy.map { |venue| Entry.new(name: venue.locality, canton: venue.canton) } +
          Place.distinct.pluck(:locality, :canton).map { |name, canton| Entry.new(name: name, canton: canton) })
    end

    def self.none = new([])

    def initialize(entries)
      @entries = entries.select { |entry| entry.name.present? }
    end

    # Identity modulo case, accents and punctuation is not a near-match: "bern" and
    # "Bern" ARE the same name, so adopting the stored spelling is a normalisation and
    # not the silent rewrite the design forbids. It matters because Location.hierarchy
    # groups on the literal string — an uncorrected "bern" is a second node in the
    # WHERE tree forever.
    #
    # A genuine variant is deliberately left alone: no string measure reaches Freiburg
    # -> Fribourg (0.29) or Genf -> Genève (0.33), and even the transposition Luzren ->
    # Luzern scores 0.27. That class needs a curated alias list, not arithmetic.
    def canonical(typed)
      matching(typed).first&.name || typed
    end

    # nil rather than a guess where the same name sits in more than one canton: Buchs
    # is a locality in SG, AG, ZH and LU alike, and answering with whichever row
    # loaded first is the wrong-canton bug this exists to prevent.
    def canton_for(typed) = canton_of(matching(typed))

    # Every name worth offering, against the canton picking it computes to — nil where
    # the name is one of the ambiguous ones and picking it settles nothing. One row per
    # town rather than per source: two spellings of the same name are the same option.
    def cantons_by_name
      by_key.values.to_h { |entries| [entries.first.name, canton_of(entries)] }
    end

    private

    attr_reader :entries

    def canton_of(entries)
      cantons = entries.filter_map { |entry| entry.canton.presence }.uniq
      cantons.first if cantons.one?
    end

    # The FINGERPRINT, not the folded form: folded keeps word boundaries (by design —
    # the trigram measure needs them), so it reads "Zorp-wil" and "Zorpwil" as
    # different. Separator-insensitivity is exactly what identity means for a town name.
    def matching(typed)
      return [] if typed.blank?

      by_key.fetch(Fingerprint.for(typed), [])
    end

    def by_key = @by_key ||= entries.group_by { |entry| Fingerprint.for(entry.name) }
  end
end
