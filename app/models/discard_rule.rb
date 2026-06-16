# An admin-authored rule that auto-discards junk scraped events by text — for
# events that carry NO genre/category, so the genre dispositions (hidden/blocked)
# can't reach them (e.g. Schüür "Tschütte" football viewings). A discard is
# re-derived from the active rule set every scrape AND on any rule change (see
# .reapply_all!), never sticky — editing or deleting a rule reverses it. That's
# the key difference from Event#dismiss! (manual, per-event, permanent).
class DiscardRule < ApplicationRecord
  has_many :discarded_events, class_name: 'Event', foreign_key: :discarded_by_rule_id,
                              inverse_of: :discarded_by_rule, dependent: :nullify

  # Length floor so a stray one-character rule can't sweep the whole table.
  validates :pattern, presence: true, length: { minimum: 2 }

  scope :active, -> { where(active: true) }
  # Deterministic order for first-match-wins in .reapply_all! and the admin list.
  scope :by_recency, -> { order(created_at: :desc) }

  # The kept events this rule currently targets — the SINGLE source of truth
  # shared by the editor preview, the "catches N" count, and .reapply_all!. A
  # case-insensitive substring (sanitized so %/_ in the pattern stay literal,
  # matching #matches?'s plain include) on title OR subtitle, optionally scoped
  # to one venue's location tag. Independent of `active` on purpose: the preview
  # shows what a rule WOULD catch while you're still toggling it.
  def matching_events
    needle = "%#{ActiveRecord::Base.sanitize_sql_like(pattern.to_s)}%"
    scope = Event.kept.where('events.title ILIKE :n OR events.subtitle ILIKE :n', n: needle)
    scope = scope.tagged_with(scraper, on: :locations) if scraper.present?
    scope
  end

  # Per-event predicate for the scrape path (Scrapers::Agent#build_event), where
  # the event isn't queryable yet. Kept behaviorally identical to
  # matching_events: same case-insensitive substring on title/subtitle, same
  # venue gate (the scraper's own location, which is one of the event's location
  # tags). `location` is the scraping venue's name.
  def matches?(title:, subtitle:, location:)
    return false if pattern.blank?
    return false if scraper.present? && scraper != location

    needle = pattern.downcase
    title.to_s.downcase.include?(needle) || subtitle.to_s.downcase.include?(needle)
  end

  # Re-derive discarded_by_rule_id across every kept event from the current
  # active rules — run after any rule create/update/destroy so existing events
  # reflect the change immediately, not just on the next scrape. First active
  # rule (newest-first) wins; clearing first means a dropped/edited rule releases
  # the events it no longer matches.
  def self.reapply_all!
    Event.kept.where.not(discarded_by_rule_id: nil).update_all(discarded_by_rule_id: nil)
    active.by_recency.each do |rule|
      ids = rule.matching_events.where(discarded_by_rule_id: nil).pluck('events.id')
      Event.where(id: ids).update_all(discarded_by_rule_id: rule.id)
    end
  end

  # Venue names offered as scope options in the editor — every registered
  # scraper's location, plus the implicit "all venues" (nil) the form adds.
  def self.venue_options
    Scrapers::All.scrapers.values.map(&:location).uniq.sort
  end
end
