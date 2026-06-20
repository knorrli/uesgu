module Scrapers
  # Non-destructive event dedup, run once at the end of a sweep (after every
  # scraper). PETZI is the primary/canonical source; where one of our bespoke
  # scrapers lists the same show (same venue + date + fuzzy title), that bespoke
  # event is pointed at the PETZI canonical (canonical_event_id) and its genres
  # are unioned onto the canonical. Duplicates are never deleted — bookmarks stay
  # intact — they're just hidden by Event.visible.
  #
  # Idempotent: each run resets every tracked bespoke event's link from scratch,
  # so a show PETZI no longer lists (or whose title drifted) re-surfaces. Genre
  # accumulation self-heals because the PETZI scrape resets the canonical's own
  # genres each sweep before this re-unions the duplicates.
  class Dedup
    PETZI_HOST = 'petzi.ch'
    MATCH_THRESHOLD = 0.4

    def self.run = new.run

    def run
      Petzi::VENUES.each_value { |loc| dedup_venue(loc.first) }
    end

    private

    # Only future, non-dismissed events for this venue are in play.
    def dedup_venue(venue)
      scope = Event.kept.where(start_date: Date.current..).tagged_with(venue, on: :locations)
      petzi   = scope.where('events.url LIKE ?', "%#{PETZI_HOST}%").to_a
      bespoke = scope.where.not('events.url LIKE ?', "%#{PETZI_HOST}%").to_a
      return if petzi.empty?

      bespoke.each do |b|
        next if b.overridden?('canonical_event') # admin-pinned merge/un-merge: leave it

        canonical = best_match(b, petzi)
        b.update_column(:canonical_event_id, canonical&.id) # nil resets a stale link
      end

      # Re-derive each canonical's genres as its own ∪ its duplicates' (auto-matched
      # AND admin-pinned), so a manual merge still enriches the canonical's genres.
      petzi.each do |p|
        merge_genres(p, bespoke.select { |b| b.canonical_event_id == p.id })
      end
    end

    # Union the duplicates' genres onto the canonical (PETZI re-set its own genres
    # this sweep, so the result is PETZI ∪ duplicates), then re-derive visibility.
    def merge_genres(canonical, dups)
      return if dups.empty?

      merged = (canonical.genre_list + dups.flat_map(&:genre_list)).uniq
      return if merged.sort == canonical.genre_list.sort

      canonical.genre_list = merged
      canonical.save!
      canonical.recompute_visibility!
    end

    # Best PETZI event for a bespoke event: same date, highest title similarity,
    # accepting a subset relationship (our club scrapers truncate "Darkside" where
    # PETZI lists the full DJ lineup) or Jaccard >= threshold.
    def best_match(bespoke, petzi_events)
      bt = tokens(bespoke.title)
      scored = petzi_events
               .select { |p| p.start_date == bespoke.start_date }
               .map do |p|
                 pt = tokens(p.title)
                 subset = !bt.empty? && !pt.empty? && (bt.subset?(pt) || pt.subset?(bt))
                 { event: p, jaccard: jaccard(bt, pt), subset: subset }
               end
      best = scored.max_by { |s| [s[:subset] ? 1 : 0, s[:jaccard]] }
      return nil unless best

      (best[:jaccard] >= MATCH_THRESHOLD || best[:subset]) ? best[:event] : nil
    end

    def jaccard(a, b)
      return 0.0 if a.empty? || b.empty?

      (a & b).size.to_f / (a | b).size
    end

    STOP = %w[the a le la les der die das und and feat featuring with vs b2b support
              live concert show tour ch us uk fr de present presents].freeze

    def tokens(title)
      title.to_s.downcase
           .tr('äöüàâéèêëïîçáí', 'aouaaeeeeiicai')
           .gsub(/\(.*?\)/, ' ')
           .gsub(/[^a-z0-9 ]/, ' ')
           .split
           .reject { |t| STOP.include?(t) || t.length < 2 }
           .to_set
    end
  end
end
