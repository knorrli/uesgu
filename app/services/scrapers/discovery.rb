require 'public_suffix'

module Scrapers
  # Source/venue discoverability. Finds venues/feeds we don't yet consume by
  # diffing upstream indices (OLE registry, Hinto ALL, PETZI sitemap) against the
  # ledger of what we've already decided on. See docs/discovery-design.md.
  #
  # This module holds the two pieces the rest of the system reconciles against:
  # the canonical-domain normalizer (#domain) and the ledger loader (Ledger).
  module Discovery
    LEDGER_PATH = Rails.root.join('config/venue_ledger.yml')

    # The canonical venue key: the registrable domain (eTLD+1), lowercased, with
    # scheme / userinfo / port / path and any subdomain ("www.", "api.", …)
    # stripped. "https://www.dachstock.ch/events" and "api.dachstock.ch" both
    # collapse to "dachstock.ch". Returns nil for blank/unparseable input or an
    # unknown public suffix (handled, not raised — a bad upstream row is skipped,
    # not fatal).
    def self.domain(url_or_host)
      host = host_of(url_or_host)
      return nil if host.blank?

      PublicSuffix.domain(host)
    rescue PublicSuffix::Error
      nil
    end

    # Extract the host from a full URL or a bare host string. A bare host has no
    # "//", so we prepend it to make URI parse it as an authority rather than a path.
    def self.host_of(value)
      str = value.to_s.strip
      return nil if str.empty?

      str = "//#{str}" unless str.include?('//')
      URI.parse(str).host&.downcase
    rescue URI::InvalidURIError
      nil
    end
    private_class_method :host_of

    # --- Discovery diff (pure; the rake fetches the upstreams and feeds them in) ---

    # The venue slug + title tail of a PETZI event URL: the bit after "/events/{id}-"
    # up to the next slash. The venue is the (multi-token) leading prefix of this,
    # but the boundary with the title is ambiguous — see #petzi_unknown_clusters.
    PETZI_EVENT_SLUG = %r{/events/\d+-([^/]+)}

    # Leading tokens we treat as the venue "stem" when clustering unknown PETZI
    # events. Two is the sweet spot: it merges a venue's events (every chat-noir
    # show stems to "chat-noir") without merging distinct venues that share only a
    # generic first token ("openair-safiental" vs "openair-am-bielersee").
    PETZI_STEM_TOKENS = 2

    # OLE registry feed URLs we consume, minus the ones already in the ledger: the
    # registrable domain of each source URL, deduped (5 refbern.ch churches collapse
    # to one), with the Hinto aggregator itself ignored.
    def self.ole_unknown_domains(source_urls, ledger, ignore: %w[hinto.ch])
      source_urls.filter_map { |u| domain(u) }
                 .reject { |d| ignore.include?(d) || ledger.known?(d) }
                 .uniq.sort
    end

    # PETZI event URLs whose venue we don't track, grouped into best-effort venue
    # clusters by their leading-token stem (see PETZI_STEM_TOKENS). The stem is a
    # guess at the venue boundary — the human reads the samples to identify the
    # venue and record slug→domain — but it reliably separates unknowns from the
    # known venues and collapses a venue's many events into one row. PETZI's own
    # non-event pages (donation links) are dropped.
    def self.petzi_unknown_clusters(event_urls, known_slugs)
      known = known_slugs.to_a
      tails = event_urls.filter_map { |u| u[PETZI_EVENT_SLUG, 1] }
                        .reject { |t| t.include?('donation') }
                        .reject { |t| known.any? { |s| t == s || t.start_with?("#{s}-") } }

      tails.group_by { |t| t.split('-').first(PETZI_STEM_TOKENS).join('-') }
           .map { |stem, members| { slug: stem, count: members.size, samples: members.first(2) } }
           .sort_by { |c| [-c[:count], c[:slug]] }
    end

    # One decided-on venue identity, keyed by canonical domain. `aliases` maps an
    # upstream ("petzi"/"ole"/"hinto") to the raw keys that resolve to this domain.
    Entry = Struct.new(:domain, :name, :disposition, :reason, :checked, :aliases,
                       keyword_init: true) do
      def consume? = disposition == 'consume'

      def blocked? = !consume?
    end

    # Loads + exposes config/venue_ledger.yml. The authoritative "have we decided
    # on this source?" record; the drift test reconciles it against the live
    # scraper registry, and the discovery report subtracts it from the upstreams.
    class Ledger
      DISPOSITIONS = %w[consume defer reject].freeze

      def self.load(path = LEDGER_PATH)
        # `checked` parses to a Date; nothing else exotic is permitted.
        data = YAML.safe_load_file(path, permitted_classes: [Date])
        new(data)
      end

      attr_reader :reasons, :entries

      def initialize(data)
        @reasons = data.fetch('reasons')
        @entries = Array(data.fetch('venues')).map { |row| build_entry(row) }
      end

      def consume_domains = entries.select(&:consume?).map(&:domain).to_set

      def domains = entries.map(&:domain).to_set

      def known?(domain) = domains.include?(domain)

      def find(domain) = entries.find { |e| e.domain == domain }

      def revisitable?(reason) = reasons.dig(reason.to_s, 'revisitable') == true

      def reason?(reason) = reasons.key?(reason.to_s)

      # An upstream raw key (a PETZI slug, an OLE/Hinto host or <location> name)
      # resolved to its canonical domain, or nil if we've never seen it. Tries the
      # explicit alias index first, then — for upstreams that expose a URL/host —
      # falls back to normalizing it (an OLE feed host auto-resolves to its eTLD+1).
      def resolve(upstream, key)
        alias_index.dig(upstream.to_s, key) || Discovery.domain(key)
      end

      # Every raw key recorded for an upstream ("petzi"/"ole"/"hinto"), across all
      # dispositions — the set discovery subtracts so a once-triaged key never
      # re-surfaces.
      def alias_keys(upstream)
        (alias_index[upstream.to_s] || {}).keys.to_set
      end

      # Blocked venues whose reason is revisitable and whose last check has gone
      # stale (default 6 months) — the discovery report re-surfaces these for a
      # fresh look (a robots.txt or a JS-only site may have changed).
      def stale_revisitable(today, months: 6)
        cutoff = today << months
        entries.select do |e|
          e.blocked? && revisitable?(e.reason) && e.checked && e.checked < cutoff
        end
      end

      # Every (upstream, raw_key) -> domain pair, for the drift test's
      # alias-uniqueness check.
      def alias_pairs
        entries.flat_map do |e|
          (e.aliases || {}).flat_map do |upstream, keys|
            Array(keys).map { |k| [upstream.to_s, k, e.domain] }
          end
        end
      end

      private

      def build_entry(row)
        Entry.new(
          domain: row.fetch('domain'),
          name: row['name'],
          disposition: row.fetch('disposition'),
          reason: row['reason'],
          checked: row['checked'],
          aliases: row['aliases'] || {}
        )
      end

      def alias_index
        @alias_index ||= entries.each_with_object({}) do |e, idx|
          (e.aliases || {}).each do |upstream, keys|
            bucket = (idx[upstream.to_s] ||= {})
            Array(keys).each { |k| bucket[k] = e.domain }
          end
        end
      end
    end
  end
end
