class CannedExtractionClient
  def self.install(...)
    corrections.clear
    EventCapture::Extractor.client_factory = -> { new(...) }
  end

  def self.uninstall = EventCapture::Extractor.client_factory = nil

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
