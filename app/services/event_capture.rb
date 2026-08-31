module EventCapture
  class ProviderError < StandardError
    attr_reader :detail

    def initialize(message, detail: nil)
      super(message)
      @detail = detail
    end
  end

  class TruncatedResponse < ProviderError; end
end
