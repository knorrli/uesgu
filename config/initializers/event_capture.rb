module EventCaptureConfig
  DEFAULT_MODEL = "google/gemma-4-31B-it"

  module_function

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
