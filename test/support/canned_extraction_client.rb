# Stands in for EventCapture::Infomaniak in browser tests: installed on the
# extractor's client factory, which exists so that a test driving the real screen
# can reach the provider call at all (see EventCapture::Extractor).
#
# It answers with provider TEXT rather than with candidates, so what it feeds still
# runs through the real JSON parse and Normalizer: the row a contributor sees is
# built the way it is in production.
class CannedExtractionClient
  # `events` are hashes in the shape EventCapture::Prompt::SCHEMA asks the model
  # for; `raises` makes every call fail the way a provider outage does.
  def self.install(...)
    corrections.clear
    EventCapture::Extractor.client_factory = -> { new(...) }
  end

  def self.uninstall = EventCapture::Extractor.client_factory = nil

  # One entry per call, nil where there was nothing to correct. Class-level because
  # the factory builds a fresh client per extraction, and a test driving the real
  # screen has no hold on the instance the Puma thread made.
  def self.corrections = @corrections ||= []

  def initialize(events: [], raises: nil)
    @events = events
    @raises = raises
  end

  def configured? = true

  def call(**args)
    self.class.corrections << args[:correction]
    raise EventCapture::ProviderError, raises if raises

    EventCapture::Infomaniak::Response.new(text: JSON.generate(events: events),
                                           model: "canned", input_tokens: 0, output_tokens: 0)
  end

  private

  attr_reader :events, :raises
end
