require "webrobots"

module EventCapture
  # One GET of a URL a contributor pasted, done the way the design doc's "The URL
  # adapter" section requires: robots.txt honoured, SSRF checked, redirects
  # followed by hand so both checks run again on every hop.
  #
  # It honours robots.txt because the alternative overturns a decision by routing
  # around it — the registry holds venues at `disposition: defer, reason: robots`,
  # and an exempt adapter means pasting a BeJazz link ingests exactly what we
  # recorded that about. The fetch also leaves our server with the scraper's UA, so
  # from the venue's logs the two are indistinguishable. A refusal is not a dead
  # end: the funnel has two other adapters, and :robots_disallowed is what tells
  # the verify screen to offer them.
  #
  # There is no per-user override. `Scrapers::Agent#respect_robots` is the escape
  # hatch, set per venue in code with a reason (the Bad Bonn precedent); a checkbox
  # on a capture form would let any contributor opt out of a call we made
  # deliberately.
  class SafeFetch
    Result = Data.define(:body, :content_type, :url, :code, :error) do
      def initialize(body: nil, content_type: nil, url: nil, code: nil, error: nil)
        super
      end

      def ok? = error.nil?
    end

    # What one hop came back as, read off the response before the socket closes.
    Fetched = Data.define(:code, :content_type, :location, :body)

    # An innocent public URL can 302 to the metadata endpoint, so the hop cap is
    # small and every hop is re-validated. 5MB is far past any event page and well
    # short of what a single Puma thread should buffer on a starter instance.
    MAX_HOPS = 4
    MAX_BYTES = 5.megabytes
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    # text/* the extractor reads as text; an image URL (a poster linked directly,
    # which is common in a chat message) feeds the image path instead. Anything
    # else — a PDF, a video, an octet-stream — is refused rather than sent to a
    # model that cannot read it.
    TEXT_TYPES = %w[text/html application/xhtml+xml text/plain].freeze
    IMAGE_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze

    def self.call(...) = new(...).call

    def initialize(url, robots: self.class.robots)
      @url = url
      @robots = robots
    end

    # One WebRobots per process, not per fetch: it caches robots.txt per origin, and
    # a fresh instance would re-request it for every paste. The cache has no TTL and
    # no bound, which at ~5 captures/day is a handful of hosts that a deploy clears.
    def self.robots
      @robots ||= WebRobots.new(Scrapers::Agent::USER_AGENT)
    end

    def call
      uri = parse
      return failure(:url_invalid, "not an http(s) URL: #{url.to_s.truncate(120)}") unless uri

      MAX_HOPS.times do
        refusal = guard(uri)
        return refusal if refusal

        response = get(uri)
        return read(response, uri) unless redirect?(response)

        uri = hop(uri, response)
        return failure(:redirect_invalid, "redirected to something that is not an http(s) URL") unless uri
      end

      failure(:too_many_redirects, "more than #{MAX_HOPS} redirects")
    rescue Timeout::Error, IOError, SystemCallError, SocketError, Net::HTTPBadResponse,
           Net::ProtocolError, OpenSSL::SSL::SSLError => e
      failure(:unreachable, "#{e.class}: #{e.message}")
    end

    private

    attr_reader :url, :robots

    def parse
      uri = URI.parse(url.to_s.strip)
      uri if uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      nil
    end

    # Order matters: the address check runs BEFORE the robots check, because
    # WebRobots fetches /robots.txt itself and that fetch is server-side too. A
    # private host would otherwise get one unvalidated request before we ever
    # decided whether to make the real one.
    def guard(uri)
      refusal = AddressCheck.refusal(uri.host)
      return failure(:address_blocked, refusal) if refusal

      disallowed(uri)
    end

    # webrobots (0.1.2) fail-closes: when the robots.txt REQUEST fails it fabricates
    # a synthetic "Disallow: /", a verdict the venue never issued. #97 established
    # the reading — unreachable is UNKNOWN, not a ban — and it matters more here
    # than in a scraper, because the fallback message would otherwise tell a
    # contributor "this site says no" about a site that never said anything.
    def disallowed(uri)
      return nil if robots.allowed?(uri)

      cause = robots.error(uri)
      return failure(:robots_disallowed, "#{uri.host}/robots.txt disallows this path") unless cause

      Rails.logger.warn(
        "[EventCapture] #{uri.host}/robots.txt is unreachable (#{cause.class}: #{cause.message}) — " \
        "no ban was published, so proceeding"
      )
      nil
    end

    def get(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        request = Net::HTTP::Get.new(uri)
        request["user-agent"] = Scrapers::Agent::USER_AGENT
        request["accept"] = (TEXT_TYPES + IMAGE_TYPES).join(", ")

        http.request(request) { |response| return capture(response) }
      end
    end

    # Read inside the block so an oversized body is abandoned mid-stream rather
    # than after it has already been held in memory.
    def capture(response)
      body = +""
      response.read_body do |chunk|
        body << chunk
        break if body.bytesize > MAX_BYTES
      end

      Fetched.new(code: response.code.to_i, content_type: response["content-type"],
                  location: response["location"], body: body)
    end

    def redirect?(response) = response.code.between?(300, 399) && response.location.present?

    def hop(uri, response)
      target = URI.join(uri, response.location)
      target if target.is_a?(URI::HTTP) && target.host.present?
    rescue URI::Error
      nil
    end

    def read(response, uri)
      return failure(:http_error, "HTTP #{response.code}") unless response.code == 200
      return failure(:too_large, "response exceeds #{MAX_BYTES / 1.megabyte}MB") if response.body.bytesize > MAX_BYTES

      type = response.content_type.to_s.split(";").first.to_s.strip.downcase
      unless TEXT_TYPES.include?(type) || IMAGE_TYPES.include?(type)
        return failure(:unsupported_content, "#{uri.host} served #{type.presence || 'no content type'}")
      end

      Result.new(body: response.body, content_type: type, url: uri.to_s)
    end

    def failure(code, error) = Result.new(code: code, error: error)
  end
end
