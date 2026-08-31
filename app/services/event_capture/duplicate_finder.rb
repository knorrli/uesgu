module EventCapture
  class DuplicateFinder
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

    def scope
      Event.kept.canonical.where(start_date: date, discarded_by_rule_id: nil)
           .tagged_with(tagged_names, on: :locations, any: true)
    end

    def tagged_names
      @tagged_names ||= [Location.resolve_venue(place)&.name || place.presence, locality.presence].compact
    end
  end
end
