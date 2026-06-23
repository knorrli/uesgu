module Scrapers
  # Non-destructive event dedup, run once at the end of a sweep (after every
  # scraper). Several sources can list the same show — a venue's OLE feed, PETZI
  # (the shared ticketing backend), and/or a bespoke HTML scraper. Where they
  # overlap (same venue + date + fuzzy title) the less-authoritative copies are
  # pointed at a single canonical (canonical_event_id) and their genres are
  # unioned onto it. Duplicates are never deleted — bookmarks stay intact — just
  # hidden by Event.visible.
  #
  # Source authority (most authoritative wins the canonical, see #source_rank).
  # We rank by which copy links most DIRECTLY to the venue's own event page:
  #   OLE  — venue-published, structured, links to the venue's OWN page; the
  #          source we're consolidating on, so it wins where present.
  #   bespoke HTML scrapers — also link to the venue's own event page, so they
  #          beat PETZI; fragile, but a successfully-parsed event is venue-direct.
  #   PETZI — shared ticketing aggregator; links to its own ticket page unless the
  #          venue exposes an official-website link, so it's the copy of LAST resort.
  # So an OLE show absorbs the matching bespoke / PETZI copies, and a bespoke show
  # absorbs the matching PETZI copy, each staying the lone visible listing. Genres
  # always accumulate onto the canonical regardless of who won it.
  #
  # Idempotent: each run re-derives every link from scratch, so a show a source
  # drops (or whose title drifts) re-surfaces. Genre accumulation self-heals
  # because each scraper resets its own event's genres each sweep before this
  # re-unions the duplicates.
  class Dedup
    MATCH_THRESHOLD = 0.4

    def self.run = new.run

    def run
      dedup_venues.each { |venue| dedup_venue(venue) }
    end

    private

    # Every venue where more than one source can land an event: the PETZI member
    # venues plus the single-venue OLE feeds. Config-driven — adding an OLE venue
    # or a PETZI member is enough, there's no separate list to maintain here.
    def dedup_venues
      ole = Ole::SOURCES.reject { |s| s[:aggregator] }.filter_map { |s| s[:location]&.first }
      (Petzi::VENUES.values.map(&:first) + ole).uniq
    end

    # All future, non-dismissed events for this venue, processed in descending
    # source authority. Each event links to the best already-seen (i.e. more-or-
    # equally authoritative) match; an event with no match becomes a canonical
    # itself and can in turn absorb the lower-authority copies that follow.
    def dedup_venue(venue)
      events = Event.kept.where(start_date: Date.current..).tagged_with(venue, on: :locations).to_a
      return if events.size < 2

      ranked     = events.sort_by { |e| [source_rank(e), e.id] }
      canonicals = []

      ranked.each do |e|
        # Admin-pinned merge/un-merge: leave the link as the admin set it. A
        # pinned standalone (link nil) still counts as a canonical others can fold
        # onto; a pinned merge keeps pointing where it was pinned.
        if e.overridden?("canonical_event")
          canonicals << e if e.canonical_event_id.nil?
          next
        end

        canonical = best_match(e, canonicals)
        e.update_column(:canonical_event_id, canonical&.id) # nil resets a stale link
        canonicals << e if canonical.nil?
      end

      # Re-derive each canonical's genres as its own ∪ its duplicates' (auto-matched
      # AND admin-pinned), so a manual merge still enriches the canonical's genres.
      canonicals.each do |c|
        merge_genres(c, ranked.select { |e| e.canonical_event_id == c.id })
      end
    end

    # 0 = OLE feed (preferred), 1 = bespoke HTML scraper, 2 = PETZI (last resort).
    # Drives which copy of an overlapping show stays visible (see class comment) —
    # we rank by which links most directly to the venue. data_source is the
    # scraper's provenance stamp ("OLE:Dachstock", "Petzi", "Dachstock", …).
    def source_rank(event)
      case event.data_source
      when /\AOLE:/ then 0
      when "Petzi"  then 2
      else 1
      end
    end

    # Union the duplicates' genres onto the canonical (the canonical's own scraper
    # re-set its genres this sweep, so the result is canonical ∪ duplicates), then
    # re-derive visibility.
    def merge_genres(canonical, dups)
      return if dups.empty?

      merged = (canonical.genre_list + dups.flat_map(&:genre_list)).uniq
      return if merged.sort == canonical.genre_list.sort

      canonical.genre_list = merged
      canonical.save!
      canonical.recompute_visibility!
    end

    # Best canonical for an event: same date, highest title similarity, accepting a
    # subset relationship (our club scrapers truncate "Darkside" where the feed
    # lists the full DJ lineup) or Jaccard >= threshold.
    def best_match(event, candidates)
      bt = tokens(event.title)
      scored = candidates
               .select { |c| c.start_date == event.start_date }
               .map do |c|
                 ct = tokens(c.title)
                 subset = !bt.empty? && !ct.empty? && (bt.subset?(ct) || ct.subset?(bt))
                 { event: c, jaccard: jaccard(bt, ct), subset: subset }
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
           .tr("äöüàâéèêëïîçáí", "aouaaeeeeiicai")
           .gsub(/\(.*?\)/, " ")
           .gsub(/[^a-z0-9 ]/, " ")
           .split
           .reject { |t| STOP.include?(t) || t.length < 2 }
           .to_set
    end
  end
end
