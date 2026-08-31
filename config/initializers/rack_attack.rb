require "ipaddr"

class Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  class Request < ::Rack::Request
    def true_ip
      @true_ip ||=
        get_header("HTTP_CF_CONNECTING_IP").presence ||
        get_header("HTTP_TRUE_CLIENT_IP").presence ||
        get_header("HTTP_X_FORWARDED_FOR").to_s.split(",").map(&:strip).find(&:present?) ||
        ip
    end

    def asset?
      path.start_with?("/assets")
    end

    FACET_QUERY = /(\A|&)(q|g|l|d|page|start_date|day|filtered)(\[\]|%5B%5D)?=/i

    def faceted?
      FACET_QUERY.match?(query_string)
    end

    def calendar_feed?
      path.start_with?("/calendar/")
    end

    def session_cookie?
      cookies.key?("_uesgu_session")
    end

    def true_ip_addr
      return @true_ip_addr if defined?(@true_ip_addr)

      @true_ip_addr = begin
        IPAddr.new(true_ip)
      rescue IPAddr::InvalidAddressError, ArgumentError
        nil
      end
    end

    def referer_host
      return nil if referer.blank?

      URI.parse(referer).host
    rescue URI::InvalidURIError
      "invalid"
    end
  end

  safelist("allow/healthcheck") { |req| req.path == "/up" }

  safelist("allow/localhost") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1"
  end

  ALLOWED_IPS = ENV.fetch("DATACENTER_ALLOW_IPS", "").split(",").filter_map do |raw|
    IPAddr.new(raw.strip)
  rescue IPAddr::InvalidAddressError, ArgumentError
    Rails.logger.warn("[Rack::Attack] ignoring unparseable DATACENTER_ALLOW_IPS entry #{raw.inspect}")
    nil
  end.freeze

  safelist("allow/manual-ip") do |req|
    next false if ALLOWED_IPS.empty?

    ip = req.true_ip_addr
    ip && ALLOWED_IPS.any? { |allowed| allowed.include?(ip) }
  end

  PROBE_PATHS = %r{
    \.php$                              |   # any PHP endpoint — install.php, xmlrpc.php, …
    /wp-(admin|login|content|includes)  |   # WordPress probes
    /(\.env|\.git|\.aws|\.ssh)\b        |   # leaked-secret probes
    /(phpmyadmin|pma|myadmin|adminer)\b |   # DB-admin panels
    /vendor/(phpunit|laravel)               # framework RCE probes
  }xi

  blocklist("block/known-probes") { |req| PROBE_PATHS.match?(req.path) }

  BOT_UA = /
    bot\b | crawler | spider | scraper |
    GPTBot | ClaudeBot | anthropic-ai | CCBot | Google-Extended |
    Bytespider | PetalBot | Amazonbot | meta-externalagent | Applebot-Extended |
    ImagesiftBot | Diffbot | Omgili | Timpibot | YouBot | perplexity |
    AhrefsBot | SemrushBot | MJ12bot | DotBot | DataForSeo | BLEXBot | Barkrowler |
    ZoominfoBot | serpstatbot | Seekport | MegaIndex |
    python-requests | python-httpx | aiohttp | scrapy | Go-http-client |
    node-fetch | axios | libwww-perl | okhttp | Java\/ | curl\/ | Wget\/ |
    HeadlessChrome | PhantomJS
  /xi

  blocklist("block/bot-user-agent") do |req|
    !req.calendar_feed? && BOT_UA.match?(req.user_agent.to_s)
  end

  blocklist("block/anonymous-facet-crawl") do |req|
    req.user_agent.to_s.strip.empty? && req.faceted? && !req.calendar_feed?
  end

  blocklist("block/datacenter-nets") do |req|
    !req.calendar_feed? && DatacenterNets.include?(req.true_ip_addr)
  end

  throttle("facets/ip", limit: 12, period: 60.seconds) do |req|
    req.true_ip if req.faceted? && !req.asset?
  end

  throttle("req/ip", limit: 60, period: 60.seconds) do |req|
    req.true_ip unless req.asset?
  end

  throttle("facets/global", limit: 120, period: 60.seconds) do |req|
    "global-facets" if req.faceted? && !req.asset?
  end

  track("measure/facets") { |req| req.faceted? && !req.asset? }

  self.throttled_responder = lambda do |req|
    match_data = req.env["rack.attack.match_data"] || {}
    retry_after = (match_data[:period] || 60).to_i
    [
      429,
      { "Content-Type" => "text/plain", "Retry-After" => retry_after.to_s },
      ["Too many requests. Please slow down and try again shortly.\n"]
    ]
  end

  self.blocklisted_responder = lambda do |req|
    if req.env["rack.attack.matched"] == "block/datacenter-nets"
      body = "Blocked: requests from this network aren't accepted.\n" \
             "Reference: #{req.true_ip_addr}\n"
      [403, { "Content-Type" => "text/plain" }, [body]]
    else
      [403, { "Content-Type" => "text/plain" }, ["Forbidden\n"]]
    end
  end
end

%w[throttle blocklist].each do |event|
  ActiveSupport::Notifications.subscribe("#{event}.rack_attack") do |_name, _start, _finish, _id, payload|
    req = payload[:request]
    Rails.logger.warn(
      "[Rack::Attack] #{event} rule=#{req.env['rack.attack.matched']} " \
      "ip=#{req.true_ip} edge=#{req.ip} #{req.request_method} #{req.fullpath} " \
      "ua=#{req.user_agent.inspect}"
    )
  end
end

ActiveSupport::Notifications.subscribe("track.rack_attack") do |_name, _start, _finish, _id, payload|
  next if ENV["PROBE_REQUESTS"].blank?

  req = payload[:request]
  Rails.logger.info(
    "[probe] session=#{req.session_cookie? ? 1 : 0} " \
    "filter_cookie=#{req.cookies.key?('events_filter') ? 1 : 0} " \
    "ref=#{req.referer_host || '-'} " \
    "ip=#{req.true_ip} edge=#{req.ip} " \
    "ua=#{req.user_agent.to_s[0, 80].inspect}"
  )
end

Rack::Attack.enabled = !Rails.env.test?
