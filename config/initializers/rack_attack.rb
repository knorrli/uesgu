# Rack::Attack — sheds abusive traffic (e.g. a scraper hammering the site) at the
# Rack layer, before the request reaches routing/controllers, so a flood costs us
# almost nothing in CPU or RAM. The web instance is a single Puma worker on 512MB
# (WEB_CONCURRENCY=1), so a sustained burst ratchets resident memory to a high-water
# mark that never comes back down — throttling keeps that peak low.
#
# August 2026 incident: a crawler that ignores robots.txt walked the feed's faceted
# URL space (the filter chips ACCUMULATE — /events?g[]=Rock offers g[]=Rock&g[]=Metal,
# which offers 170+ more, so the reachable URL set is combinatorial and effectively
# infinite) at ~1 req/s for ten days. ~55k full page renders/day × ~18KB gzipped
# ≈ 1GB/day — it burned the entire 5GB/month bandwidth allowance twice over.
# Every defense below exists because of a specific way that crawl got through.
class Rack::Attack
  # rack-attack defaults to Rails.cache for counters, but production has no explicit
  # cache_store (it can silently resolve to :null_store, which would make every
  # throttle a no-op). With a single Puma worker there is exactly one process, so an
  # in-process memory store counts accurately. NOTE: if WEB_CONCURRENCY is ever raised
  # above 1, switch this to a shared store (Solid Cache / Redis) or each worker will
  # count independently and the effective limit becomes workers × limit.
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  ### Request helpers ###################################################

  # THE bug that made every throttle below useless until now: Render terminates TLS
  # at a Cloudflare edge (confirmed — even uesgu.onrender.com answers with
  # `server: cloudflare` + `cf-ray`), so `req.ip` is ALWAYS a CLOUDFLARENET address,
  # never the real client. During the incident a single crawler arrived over 12
  # distinct edge IPs inside 41 seconds, so a per-IP limit of 60/min saw ~5/min per
  # key and never fired. Keying on the true client is what makes rate limiting work
  # at all here.
  #
  # We do not choose, control, or pay Cloudflare — it is Render's front door, and
  # blocklisting those ranges would black out the site for every real visitor too.
  # CF-Connecting-IP is simply the header that front door stamps with the origin
  # client; Cloudflare overwrites it on every request, so unlike X-Forwarded-For it
  # cannot be spoofed from outside. XFF's leftmost entry is the vendor-neutral
  # equivalent and is kept as a fallback, but it is attacker-controlled — prefer the
  # unspoofable one, or a crawler evades every limit below by inventing a new
  # client IP per request.
  class Request < ::Rack::Request
    def true_ip
      @true_ip ||=
        get_header("HTTP_CF_CONNECTING_IP").presence ||
        get_header("HTTP_TRUE_CLIENT_IP").presence ||
        get_header("HTTP_X_FORWARDED_FOR").to_s.split(",").map(&:strip).find(&:present?) ||
        ip
    end

    # Fingerprinted assets are served/cached by Thruster and are cheap; excluding
    # them keeps a real first-time visitor's cold page load (many /assets fetches
    # via importmap) from eating their own request budget.
    def asset?
      path.start_with?("/assets")
    end

    # A request into the combinatorial filter space — the expensive surface. Matched
    # on the raw query string (cheap) rather than parsing nested params on every hit.
    # `filtered` is included because it is the redirect amplifier: /events?filtered=1&…
    # 302s to the clean URL, so each crawled facet cost ~1.6 requests, not 1.
    FACET_QUERY = /(\A|&)(q|g|l|d|page|start_date|day|filtered)(\[\]|%5B%5D)?=/i

    def faceted?
      FACET_QUERY.match?(query_string)
    end

    # Subscribable ICS feed: real calendar clients (Apple, Google, Thunderbird) poll
    # it on a schedule with bot-shaped or absent User-Agents, so it must never be
    # caught by the UA rules below. It is token-guarded and small; it still counts
    # against the per-IP throttle.
    def calendar_feed?
      path.start_with?("/calendar/")
    end
  end

  ### Safelists — never throttled #######################################

  # Render's healthcheck. Throttling it would take the whole instance down.
  safelist("allow/healthcheck") { |req| req.path == "/up" }

  # Local traffic (dev console, system tests poking the app). Deliberately keyed on
  # the transport-level ip, not true_ip — a forged CF-Connecting-IP: 127.0.0.1 must
  # not buy an outside client a safelist.
  safelist("allow/localhost") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1"
  end

  ### Blocklists — dropped outright, before routing #####################

  # Vulnerability scanners and script-kiddie bots constantly probe for software we
  # don't run (WordPress, phpMyAdmin, exposed .env/.git, …). None of these paths can
  # ever be legitimate on this Rails app — there is no PHP and we never serve dotfiles
  # — so we drop them at the Rack layer. This kills the ActionController::RoutingError
  # noise they'd otherwise generate (see the /wp-admin/install.php floods) and costs
  # next to nothing. Anchored/substring branches each match independently; req.path
  # excludes the query string, so ".../install.php?step=1" still matches \.php$.
  PROBE_PATHS = %r{
    \.php$                              |   # any PHP endpoint — install.php, xmlrpc.php, …
    /wp-(admin|login|content|includes)  |   # WordPress probes
    /(\.env|\.git|\.aws|\.ssh)\b        |   # leaked-secret probes
    /(phpmyadmin|pma|myadmin|adminer)\b |   # DB-admin panels
    /vendor/(phpunit|laravel)               # framework RCE probes
  }xi

  blocklist("block/known-probes") { |req| PROBE_PATHS.match?(req.path) }

  # Self-identifying crawlers: SEO/marketing spiders, AI training scrapers, and bare
  # HTTP clients. üsgu is invite-only and carries a sitewide noindex — there is no
  # audience for it in a search index or a training set, so none of these has any
  # business here and all are dropped before routing. robots.txt already says
  # "Disallow: /" to everyone; this enforces it against the ones that don't read it.
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

  # A crawler that hides behind a blank User-Agent still has to send a query string
  # to walk the facet space. Every real browser sends a UA, so "no UA + faceted URL"
  # is never a human. Bare paths are left alone so a UA-less curl of the homepage
  # (uptime checks, a quick sanity probe) keeps working.
  blocklist("block/anonymous-facet-crawl") do |req|
    req.user_agent.to_s.strip.empty? && req.faceted? && !req.calendar_feed?
  end

  ### Throttles #########################################################

  # The facet space is what actually costs money: each hit is a full ~18KB render
  # behind 25-30 SQL queries and 200-600ms of CPU. A human browsing makes ONE such
  # request per interaction (assets are excluded, and Turbo reuses the frame), so 12
  # a minute is generous for a person and ruinous for a crawler running at 60/min.
  # Deliberately tighter than the general cap and checked first.
  throttle("facets/ip", limit: 12, period: 60.seconds) do |req|
    req.true_ip if req.faceted? && !req.asset?
  end

  # General per-IP cap for everything else — unfiltered pages, form posts, the ICS
  # feed. Far above a human's browsing rate, well below a crawl.
  throttle("req/ip", limit: 60, period: 60.seconds) do |req|
    req.true_ip unless req.asset?
  end

  # Backstop against a genuinely distributed crawl (a botnet, or a client forging
  # X-Forwarded-For to mint a fresh identity per request — possible only if
  # CF-Connecting-IP ever stops arriving). Counts ALL faceted traffic site-wide
  # against one bucket. üsgu serves a closed invite list, so real aggregate demand
  # is a few requests a minute; 120/min leaves enormous headroom while still capping
  # the worst case at roughly 3% of the bandwidth this incident burned.
  throttle("facets/global", limit: 120, period: 60.seconds) do |req|
    "global-facets" if req.faceted? && !req.asset?
  end

  ### Responses #########################################################

  self.throttled_responder = lambda do |req|
    match_data = req.env["rack.attack.match_data"] || {}
    retry_after = (match_data[:period] || 60).to_i
    [
      429,
      { "Content-Type" => "text/plain", "Retry-After" => retry_after.to_s },
      ["Too many requests. Please slow down and try again shortly.\n"]
    ]
  end

  # Blocked clients get a flat 403 with no body worth parsing — cheapest possible
  # answer, and nothing that hints at what to change to get through.
  self.blocklisted_responder = lambda do |_req|
    [403, { "Content-Type" => "text/plain" }, ["Forbidden\n"]]
  end
end

### Logging ###########################################################

# Emit a clear WARN line whenever a request is throttled or blocked, so "rate
# limiting is working" is obvious in the Render logs (the bare 429/403 status line
# is easy to miss). Logs BOTH the resolved true client IP and the Cloudflare edge
# IP: if true_ip ever collapses back to a CLOUDFLARENET address, IP throttling has
# silently broken again and this line is how we find out.
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

# Keep the middleware out of the test suite so system/integration tests can hammer
# the app without tripping the throttle. The rack_attack test overrides this locally.
Rack::Attack.enabled = !Rails.env.test?
