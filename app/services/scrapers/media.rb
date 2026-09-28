module Scrapers
  module Media
    LIMIT = 5

    PROVIDERS = {
      "youtube" => %r{(?:youtube(?:-nocookie)?\.com/(?:embed/|shorts/|live/|watch\?(?:[^"'\s]*?&)?v=)|youtu\.be/|(?:img\.youtube\.com|i\.ytimg\.com)/vi/)([\w-]{11})}i,
      "vimeo" => %r{(?:player\.vimeo\.com/video/|(?<![\w.])(?:www\.)?vimeo\.com/)(\d{5,})}i,
      "bandcamp" => %r{bandcamp\.com/EmbeddedPlayer/(?:v=2/)?((?:album|track)=\d+)}i,
      "soundcloud" => %r{(?<![\w.])(?:www\.)?soundcloud\.com/((?!pages/|discover|search|upload|you/|user-)[\w-]+/[\w-]+(?:/sets/[\w-]+)?)|api\.soundcloud\.com(?:/|%2F)(tracks|playlists)(?:/|%2F)(?:soundcloud(?::|%3A|%253A)\w+(?::|%3A|%253A))?(\d+)}i,
      "mixcloud" => %r{(?<![\w.])(?:www\.)?mixcloud\.com/((?!widget/|discover/|upload/)[\w-]+/[\w-]+)}i,
      "spotify" => %r{open\.spotify\.com/(?:embed/)?(?:intl-\w+/)?((?:artist|album|track|playlist)/\w{22})}i
    }.freeze

    OUTSIDE_SITE_CHROME = "descendant-or-self::*[not(ancestor-or-self::header or ancestor-or-self::footer " \
                          "or ancestor-or-self::nav or ancestor-or-self::aside)]/@*".freeze

    module_function

    def in(content)
      content = content.parser if content.respond_to?(:parser)

      case content
      when Nokogiri::XML::Node then ranked(content.xpath(OUTSIDE_SITE_CHROME).map(&:value))
      when Hash, Array then ranked(strings_in(content))
      else []
      end
    end

    def ranked(values)
      references = values.flat_map { |value| in_text(value) }.uniq
      references.sort_by.with_index { |ref, i| [PROVIDERS.keys.index(ref["provider"]), i] }.first(LIMIT)
    end

    def in_text(text)
      PROVIDERS.flat_map do |provider, pattern|
        text.scan(pattern).map { |captures| { "provider" => provider, "id" => captures.compact.join("/") } }
      end
    end

    def strings_in(data)
      case data
      when Hash then data.values.flat_map { |value| strings_in(value) }
      when Array then data.flat_map { |value| strings_in(value) }
      when String then [data]
      else []
      end
    end
  end
end
