# Extraction provider config for user event capture, mirroring
# config/initializers/web_push.rb and mail.rb: supply the credentials through env
# (INFOMANIAK_API_TOKEN / INFOMANIAK_PRODUCT_ID) or credentials
# (infomaniak.api_token / infomaniak.product_id) and capture works; leave them
# absent and the feature is inert — EventCaptureConfig.configured? is false and
# EventCapture::Extractor returns an unconfigured failure instead of raising, so
# dev/CI/first deploy all boot fine.
#
# The provider is settled by the bake-off in docs/user-event-capture-design.md:
# Gemma 4 31B on Infomaniak, Swiss-hosted, 0/6 fabricated dates, ~6 cents/month.
# The token needs the `ai-tools` scope; the product id is the AI product it is
# issued against (`ruby script/event_capture_bakeoff.rb --list-infomaniak` prints
# both it and the model ids).
module EventCaptureConfig
  # Model ids are per-vendor strings with no discovery at boot, so this is a
  # constant with an env override rather than something we resolve at runtime —
  # swapping models is a deliberate act (a prompt tuned for one model does NOT
  # transfer to another; see "Two findings worth keeping" in the design doc).
  DEFAULT_MODEL = "google/gemma-4-31B-it"

  module_function

  # Trimmed, and forced to a string: a value pasted with a trailing newline makes
  # Net::HTTP raise on the header, and a product id stored as a YAML integer has no
  # `.presence`. Both would surface as an unhandled exception rather than as the
  # "not configured" the caller knows how to show.
  def api_token
    trimmed(ENV["INFOMANIAK_API_TOKEN"]) || trimmed(Rails.application.credentials.dig(:infomaniak, :api_token))
  end

  def product_id
    trimmed(ENV["INFOMANIAK_PRODUCT_ID"]) || trimmed(Rails.application.credentials.dig(:infomaniak, :product_id))
  end

  def trimmed(value) = value.to_s.strip.presence

  def model
    ENV["INFOMANIAK_MODEL"].presence || DEFAULT_MODEL
  end

  def configured?
    api_token.present? && product_id.present?
  end
end
