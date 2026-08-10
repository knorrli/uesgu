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
require "ipaddr"

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

    # Rails sets _uesgu_session on the first response to EVERY visitor, signed in or
    # not. So this asks "has this client been here before AND does it keep cookies?",
    # NOT "is this client logged in" — anonymous browsing stays fully supported, and
    # an account only buys persisted filters. The only humans who answer false are
    # first-request-of-a-fresh-client, e.g. a cold click on a shared filtered link.
    def session_cookie?
      cookies.key?("_uesgu_session")
    end

    # Parsed form of true_ip, or nil when it isn't a usable address. Memoised through
    # `defined?` rather than `||=` so a nil result isn't re-parsed (and re-raised) on
    # every rule that consults it.
    def true_ip_addr
      return @true_ip_addr if defined?(@true_ip_addr)

      @true_ip_addr = begin
        IPAddr.new(true_ip)
      rescue IPAddr::InvalidAddressError, ArgumentError
        nil
      end
    end

    # Host only, deliberately never the full URL: enough to separate "followed one of
    # our own chip links" from "arrived cold", without writing visitors' browsing
    # paths into the logs. See the privacy note on the probe subscriber below.
    def referer_host
      return nil if referer.blank?

      URI.parse(referer).host
    rescue URI::InvalidURIError
      "invalid"
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

  # Escape hatch for a false positive. The datacenter list below is generated from
  # third-party feeds, so the day it wrongly catches a real user the fix has to be
  # faster than a release: this is a comma-separated list of addresses or CIDRs
  # (DATACENTER_ALLOW_IPS on Render) that bypasses every rule in this file. An
  # env-var change restarts the worker — no PR, no CI, no tag.
  #
  # Keyed on true_ip, unlike the localhost safelist: CF-Connecting-IP is stamped by
  # Render's edge on every request and cannot be forged from outside, so there is
  # nothing here for an attacker to aim at. Garbage entries are dropped rather than
  # raised on — a typo in an env var must not take the site down at boot.
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

  # Cloud/datacenter networks with no plausible human audience here. Established by
  # measurement rather than assumption (the [probe] instrumentation from #82): over a
  # 7-minute window, ALL 431 faceted requests came from Alibaba Cloud, rotating across
  # 118 client IPs, and zero came from anywhere else.
  #
  # This rule exists because every cheaper discriminator was measured and found dead:
  # the crawler carries a session cookie on 100% of requests and a plausible
  # same-origin referer on 43%, and it is spread thinly enough across its pool that no
  # per-IP cap ever trips (118 IPs in 7 minutes; the 12/min facet limit saw nothing).
  # The source network was the only signal that separated it from a visitor — and it
  # separated perfectly.
  #
  # Whole allocations rather than the individual addresses seen, so rotation inside
  # a provider's pool doesn't evade it. üsgu is invite-only with a handful of users
  # in Switzerland; none of them browses from a datacenter in Singapore. A posture
  # this blunt would be reckless for a public site and is proportionate here.
  #
  # The crawler did not stop when the Alibaba block landed — it kept driving ~1.3
  # req/s into 403s, so rotating to another cloud was always its next move. Rather
  # than wait to lose the IP signal, the list now covers the compute providers it
  # could rotate to: AWS, GCP, Azure, Hetzner, OVH, DigitalOcean, Linode, Vultr,
  # Scaleway, Oracle, Contabo, Alibaba, Tencent, Huawei (~13.7k CIDRs, generated
  # into config/datacenter_nets.txt by `bin/rails datacenter_nets:refresh`).
  #
  # It covers COMPUTE only and deliberately not CDN or consumer-proxy egress —
  # blocking Cloudflare/Fastly/Akamai/Apple would catch iCloud Private Relay users,
  # and blocking Google beyond GCP would catch Chrome's IP Protection. Real people
  # do come through those. See lib/datacenter_nets.rb and issue #85 for the full
  # reasoning, including why Swiss consumer ISPs cannot collide with any of this.
  #
  # The calendar exemption is load-bearing: /calendar/:token is polled by Google,
  # Apple and Microsoft SERVERS on the subscriber's behalf, from exactly the ranges
  # this rule blocks. Without it, adding Azure would silently stop every ICS
  # subscription — the subscriber sees stale events, not an error, so neither side
  # would ever find out. The feed is token-guarded, cheap, and still counts against
  # the per-IP throttle.
  blocklist("block/datacenter-nets") do |req|
    !req.calendar_feed? && DatacenterNets.include?(req.true_ip_addr)
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

  ### Measurement — matches, never blocks ###############################

  # Temporary diagnostic. The Aug 2026 crawl survived every rule above: it is spread
  # across a large pool of client IPs (so the per-IP caps never trip — measured at
  # ~39 faceted renders/min site-wide, with no single client near the 12/min limit)
  # and it sends realistic browser User-Agents (so the UA blocklist misses it).
  #
  # Per-IP limits are structurally the wrong instrument against a distributed crawl,
  # so the next rule has to key on something that separates a bot from a visitor.
  # Rather than guess which signal that is, measure it: `track` matches a request and
  # fires a notification WITHOUT blocking, throttling, or altering the response, so
  # this is pure observation. The subscriber below decides whether to log.
  track("measure/facets") { |req| req.faceted? && !req.asset? }

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
  #
  # The network block is the one exception. It is the only rule that could plausibly
  # catch a real person (the ranges come from third-party feeds and are not verified
  # against our own traffic), and a bare "Forbidden" is indistinguishable from the
  # site being down — a false positive would read as an outage and never get
  # reported. So that rule alone names itself and echoes the address, which is all a
  # user needs to say "üsgu is blocking me, it says 203.0.113.5".
  #
  # Deliberately NOT a contact address: this body is served to every blocked crawler,
  # and 403 endpoints are exactly what address harvesters chew through. The user base
  # is a handful of people who already have a direct line. Deliberately no hint that
  # a different network would work, and text/plain so there is nothing to render.
  #
  # The address is echoed from the PARSED form, never the raw header, so an
  # attacker-supplied X-Forwarded-For cannot put arbitrary bytes in a response body.
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

# One line per faceted request, answering the single question the next rule depends
# on: does the traffic burning the bandwidth carry a session cookie or a referer?
# Query it with `render logs --text "[probe]"` and compare the session=1 / session=0
# split against the known ~39 faceted req/min.
#
# PRIVACY: presence booleans only — never cookie VALUES. A session cookie written to
# a log is a hijackable credential for anyone who can read logs, which is a genuine
# vulnerability rather than a style point. Same reason the referer is reduced to its
# host: we need "own link vs. cold arrival", not visitors' browsing paths.
#
# Gated at request time rather than at boot so the switch is a Render env-var flip,
# and so the test suite can exercise the whole path. Delete this block (and the
# `track` rule above) once the shedding rule it informs has landed.
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

# Keep the middleware out of the test suite so system/integration tests can hammer
# the app without tripping the throttle. The rack_attack test overrides this locally.
Rack::Attack.enabled = !Rails.env.test?
