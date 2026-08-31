module Scrapers
  class Dedup
    def self.run = new.run

    def run
      dedup_venues.each { |venue| dedup_venue(venue) }
    end

    private

    def dedup_venues
      (Petzi.venues.values.map(&:first) + Venue.consuming.map(&:name) +
        Place.canonicals.pluck(:name)).uniq
    end

    def dedup_venue(venue)
      events = Event.kept.where(start_date: Date.current..).tagged_with(venue, on: :locations).to_a
      return if events.size < 2

      ranked     = events.sort_by { |e| [source_rank(e), -e.id] }
      canonicals = []

      ranked.each do |e|
        if e.overridden?("canonical_event")
          canonicals << e if e.canonical_event_id.nil?
          next
        end

        canonical = best_match(e, canonicals)
        e.update_column(:canonical_event_id, canonical&.id)
        canonicals << e if canonical.nil?
      end

      canonicals.each do |c|
        CanonicalEnrichment.call(c, ranked.select { |e| e.canonical_event_id == c.id })
      end
    end

    def source_rank(event)
      case event.data_source
      when /\AOLE:/ then 0
      when "Petzi"  then 2
      when EventCapture::Creator::DATA_SOURCE then 3
      else 1
      end
    end

    def best_match(event, candidates)
      bt = TitleSimilarity.tokens(event.title)
      scored = candidates
               .select { |c| c.start_date == event.start_date && time_compatible?(event, c) }
               .map do |c|
                 ct = TitleSimilarity.tokens(c.title)
                 { event: c, jaccard: TitleSimilarity.jaccard(bt, ct),
                   subset: TitleSimilarity.subset?(bt, ct) }
               end
      best = scored.max_by { |s| [s[:subset] ? 1 : 0, s[:jaccard]] }
      return nil unless best

      (best[:jaccard] >= TitleSimilarity::THRESHOLD || best[:subset]) ? best[:event] : nil
    end

    def time_compatible?(event, candidate)
      return true if candidate.data_source != event.data_source

      candidate.start_time == event.start_time
    end
  end
end
