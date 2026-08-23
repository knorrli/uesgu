module EventCapture
  # Events the app already carries that look like the one on a capture card — the
  # few worth putting in front of a contributor as "is it one of these?".
  #
  # A PROPOSAL, never a merge. That is what separates it from the nightly
  # Scrapers::Dedup, which auto-folds and so may only look within one venue: this
  # also matches on the town alone, because the captures most likely to duplicate
  # something are the ones for a venue the registry does not cover, and there is no
  # venue name to meet on. A town is far too wide a net to fold on unattended — two
  # unrelated shows in Bern on one night would collide — but exactly right when a
  # human reads the answer and decides.
  #
  # Title matching is TitleSimilarity, the same rule and threshold the sweep folds
  # on, so the card cannot propose a pairing the sweep would refuse to keep.
  class DuplicateFinder
    # Enough to recognise the show, few enough to read without scrolling the card.
    LIMIT = 3

    def self.for(...) = new(...).call

    def initialize(title:, date:, place: nil, locality: nil)
      @title = title.to_s.strip
      @date = date
      @place = place.to_s.strip
      @locality = locality.to_s.strip
    end

    def call
      return [] if title.blank? || date.blank? || tagged_names.empty? || tokens.empty?

      scope.map { |event| [event, TitleSimilarity.tokens(event.title)] }
           .select { |_event, other| TitleSimilarity.match?(tokens, other) }
           .sort_by { |_event, other| -TitleSimilarity.jaccard(tokens, other) }
           .first(LIMIT)
           .map(&:first)
    end

    private

    attr_reader :title, :date, :place, :locality

    def tokens = @tokens ||= TitleSimilarity.tokens(title)

    # Hidden events are deliberately IN: an event the music gate hid for carrying only
    # non-music genres is one a poster-read genre can legitimately lift, and it is
    # still the same show either way. Dismissed and rule-discarded ones are out — an
    # admin threw those away, and offering to enrich one would walk it back.
    def scope
      Event.kept.canonical.where(start_date: date, discarded_by_rule_id: nil)
           .tagged_with(tagged_names, on: :locations, any: true)
    end

    # The venue as the taxonomy spells it, because that is what the event carries:
    # a contributor typing a variant the registry folds ("AKUT Thun" → "AKuT") would
    # otherwise match nothing. Location.resolve_venue is the same lookup Creator
    # publishes through.
    def tagged_names
      @tagged_names ||= [Location.resolve_venue(place)&.name || place.presence, locality.presence].compact
    end
  end
end
