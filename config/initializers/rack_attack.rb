# Rack::Attack — sheds abusive traffic (e.g. a scraper hammering the site) at the
# Rack layer, before the request reaches routing/controllers, so a flood costs us
# almost nothing in CPU or RAM. The web instance is a single Puma worker on 512MB
# (WEB_CONCURRENCY=1), so a sustained burst ratchets resident memory to a high-water
# mark that never comes back down — throttling keeps that peak low.
class Rack::Attack
  # rack-attack defaults to Rails.cache for counters, but production has no explicit
  # cache_store (it can silently resolve to :null_store, which would make every
  # throttle a no-op). With a single Puma worker there is exactly one process, so an
  # in-process memory store counts accurately. NOTE: if WEB_CONCURRENCY is ever raised
  # above 1, switch this to a shared store (Solid Cache / Redis) or each worker will
  # count independently and the effective limit becomes workers × limit.
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  ### Safelists — never throttled #######################################

  # Render's healthcheck. Throttling it would take the whole instance down.
  safelist("allow/healthcheck") { |req| req.path == "/up" }

  # Local traffic (dev console, system tests poking the app).
  safelist("allow/localhost") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1"
  end

  ### Throttles #########################################################

  # Per-IP request cap. Strict by design: 60 dynamic requests/minute is far above a
  # human browsing the site but well below a bot crawling listings/calendar months.
  # Fingerprinted assets are skipped (returning nil ⇒ not counted): a single cold
  # page load pulls many /assets requests via importmap, and counting those would
  # punish real first-time visitors. Thruster fronts and caches assets anyway, so
  # most never reach this layer.
  throttle("req/ip", limit: 60, period: 60.seconds) do |req|
    req.ip unless req.path.start_with?("/assets")
  end

  ### Response for throttled requests ###################################

  self.throttled_responder = lambda do |req|
    match_data = req.env["rack.attack.match_data"] || {}
    retry_after = (match_data[:period] || 60).to_i
    [
      429,
      { "Content-Type" => "text/plain", "Retry-After" => retry_after.to_s },
      ["Too many requests. Please slow down and try again shortly.\n"]
    ]
  end
end

### Logging ###########################################################

# Emit a clear WARN line whenever a request is throttled, so "rate limiting is
# working" is obvious in the Render logs (the bare 429 status line is easy to miss).
ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  Rails.logger.warn(
    "[Rack::Attack] throttled rule=#{req.env['rack.attack.matched']} " \
    "ip=#{req.ip} #{req.request_method} #{req.fullpath} ua=#{req.user_agent.inspect}"
  )
end

# Keep the middleware out of the test suite so system/integration tests can hammer
# the app without tripping the throttle.
Rack::Attack.enabled = !Rails.env.test?
