module Scrapers
  module Media
    LIMIT = 5

    PROVIDERS = {
      "youtube" => %r{(?:youtube(?:-nocookie)?\.com/(?:embed/|shorts/|live/|watch\?(?:[^"'\s]*?&)?v=)|youtu\.be/|(?:img\.youtube\.com|i\.ytimg\.com)/vi/)([\w-]{11})}i,
      "vimeo" => %r{(?:player\.vimeo\.com/video/|(?<![\w.])(?:www\.)?vimeo\.com/)(\d{5,})}i,
      "bandcamp" => %r{bandcamp\.com/EmbeddedPlayer/(?:v=2/)?((?:album|track)=\d+)}i,
      "soundcloud" => %r{(?<![\w.])(?:www\.)?soundcloud\.com/((?!pages/|discover|search|upload|you/|user-)[\w-]+/[\w-]+(?:/sets/[\w-]+)?)|api\.soundcloud\.com(?:/|%2F)((?:tracks|playlists)(?:/|%2F)\d+)}i,
      "mixcloud" => %r{(?<![\w.])(?:www\.)?mixcloud\.com/((?!widget/|discover/|upload/)[\w-]+/[\w-]+)}i,
      "spotify" => %r{open\.spotify\.com/(?:embed/)?(?:intl-\w+/)?((?:artist|album|track|playlist)/\w{22})}i
    }.freeze

    OUTSIDE_SITE_CHROME = "descendant-or-self::*[not(ancestor-or-self::header or ancestor-or-self::footer " \
                          "or ancestor-or-self::nav or ancestor-or-self::aside)]/@*".freeze

    module_function

    def in(content)
      node = content.respond_to?(:parser) ? content.parser : content
      return [] unless node.is_a?(Nokogiri::XML::Node)

      references = node.xpath(OUTSIDE_SITE_CHROME).flat_map { |attribute| in_text(attribute.value) }
      references.uniq.sort_by.with_index { |ref, i| [PROVIDERS.keys.index(ref["provider"]), i] }.first(LIMIT)
    end

    def in_text(text)
      PROVIDERS.flat_map do |provider, pattern|
        text.scan(pattern).map { |ids| { "provider" => provider, "id" => normalize(provider, ids.compact.first) } }
      end
    end

    def normalize(provider, id)
      provider == "soundcloud" ? id.gsub("%2F", "/") : id
    end
  end
end
