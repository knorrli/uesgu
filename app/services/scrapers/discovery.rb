require "public_suffix"

module Scrapers
  module Discovery
    def self.domain(url_or_host)
      host = host_of(url_or_host)
      return nil if host.blank?

      PublicSuffix.domain(host)
    rescue PublicSuffix::Error
      nil
    end

    def self.host_of(value)
      str = value.to_s.strip
      return nil if str.empty?

      str = "//#{str}" unless str.include?("//")
      URI.parse(str).host&.downcase
    rescue URI::InvalidURIError
      nil
    end
    private_class_method :host_of

    PETZI_EVENT_SLUG = %r{/events/\d+-([^/]+)}

    PETZI_STEM_TOKENS = 2

    def self.ole_unknown_domains(source_urls, ledger, ignore: %w[hinto.ch])
      source_urls.filter_map { |u| domain(u) }
                 .reject { |d| ignore.include?(d) || ledger.known?(d) }
                 .uniq.sort
    end

    def self.petzi_unknown_clusters(event_urls, known_slugs)
      known = known_slugs.to_a
      tails = event_urls.filter_map { |u| u[PETZI_EVENT_SLUG, 1] }
                        .reject { |t| t.include?("donation") }
                        .reject { |t| known.any? { |s| t == s || t.start_with?("#{s}-") } }

      tails.group_by { |t| t.split("-").first(PETZI_STEM_TOKENS).join("-") }
           .map { |stem, members| { slug: stem, count: members.size, samples: members.first(2) } }
           .sort_by { |c| [-c[:count], c[:slug]] }
    end

    Entry = Struct.new(:domain, :name, :disposition, :reason, :checked, :aliases,
                       keyword_init: true) do
      def consume? = disposition == "consume"

      def blocked? = !consume?
    end

    class Ledger
      DISPOSITIONS = %w[consume defer reject].freeze

      REASONS = {
        "robots"       => { "revisitable" => true,  "explanation" => "robots.txt disallows the feed/pages we'd need for our UA. May change; opting out is a deliberate per-venue call (cf. Scrapers::BadBonn)." },
        "js_only"      => { "revisitable" => true,  "explanation" => "Events render via JavaScript with no machine-readable data, and Mechanize can't run JS. Re-check: sites add JSON-LD / a JSON API." },
        "no_date"      => { "revisitable" => true,  "explanation" => "Listings exist but carry no scrapeable date/time (e.g. a WP REST endpoint exposing the post date, not the event date)." },
        "inactive"     => { "revisitable" => true,  "explanation" => "Feed/site exists but is unmaintained — stale or frozen data. Worth re-checking in case it revives." },
        "needs_work"   => { "revisitable" => true,  "explanation" => "Wanted, but needs significant custom integration (scale, per-event keying, music-only filtering) before clean ingest. A build task, not a venue defect." },
        "feed_quality" => { "revisitable" => true,  "explanation" => "Feed parses but is too poor to ingest cleanly — no per-event URLs, no structured genres, or addresses jammed into the venue name." },
        "non_music"    => { "revisitable" => false, "explanation" => "Not a music venue (cinema, cabaret/Kleinkunst, theatre, museum). Its programme would flood the taxonomy with non-music genres." },
        "promoter"     => { "revisitable" => false, "explanation" => "A roving promoter/series with no fixed venue — events scatter across guest venues we already cover. Following it would mislead and duplicate." }
      }.freeze

      def self.load(_path = nil)
        new("reasons" => REASONS, "venues" => Venue.all.map { |v| row_for(v) })
      end

      def self.row_for(venue)
        {
          "domain" => venue.domain,
          "name" => venue.name,
          "disposition" => venue.disposition,
          "reason" => venue.reason&.to_s,
          "checked" => venue.checked,
          "aliases" => venue.aliases
        }
      end

      attr_reader :reasons, :entries

      def initialize(data)
        @reasons = data.fetch("reasons")
        @entries = Array(data.fetch("venues")).map { |row| build_entry(row) }
      end

      def consume_domains = entries.select(&:consume?).map(&:domain).to_set

      def domains = entries.map(&:domain).to_set

      def known?(domain) = domains.include?(domain)

      def find(domain) = entries.find { |e| e.domain == domain }

      def revisitable?(reason) = reasons.dig(reason.to_s, "revisitable") == true

      def reason?(reason) = reasons.key?(reason.to_s)

      def resolve(upstream, key)
        alias_index.dig(upstream.to_s, key) || Discovery.domain(key)
      end

      def alias_keys(upstream)
        (alias_index[upstream.to_s] || {}).keys.to_set
      end

      def stale_revisitable(today, months: 6)
        cutoff = today << months
        entries.select do |e|
          e.blocked? && revisitable?(e.reason) && e.checked && e.checked < cutoff
        end
      end

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
          domain: row.fetch("domain"),
          name: row["name"],
          disposition: row.fetch("disposition"),
          reason: row["reason"],
          checked: row["checked"],
          aliases: row["aliases"] || {}
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
