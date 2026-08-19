module EventCapture
  # What an adapter hands the Extractor: one thing the model can read, or one
  # failure saying why there isn't one. Returned rather than raised, for the same
  # reason Extraction is — in a bulk capture a single bad input is one row to
  # retry, not a dead batch.
  #
  # `code` is a symbol and `error` is developer-facing English (rake, logs). The
  # verify screen (#106) chooses its own three-locale copy per code rather than
  # rendering these strings: a service returning translated prose would put UI
  # copy behind a rake task nobody translates.
  Input = Data.define(:kind, :image_data, :media_type, :text, :code, :error) do
    def self.image(image_data, media_type:) = new(kind: :image, image_data: image_data, media_type: media_type)

    def self.text(text) = new(kind: :text, text: text)

    def self.failure(code, error) = new(code: code, error: error)

    def initialize(kind: nil, image_data: nil, media_type: nil, text: nil, code: nil, error: nil)
      super
    end

    def ok? = error.nil?
    def image? = kind == :image
  end
end
