module EventCapture
  # What an adapter hands the Extractor: one thing the model can read, or one
  # failure saying why there isn't one. Returned rather than raised, for the same
  # reason Extraction is — in a bulk capture a single bad input is one row to
  # retry, not a dead batch.
  #
  # `code` is a symbol and `error` is developer-facing English (rake, logs). The
  # verify screen (#106) chooses its own three-locale copy per code rather than
  # rendering these strings: a service returning translated prose would put UI
  # copy behind a rake task nobody translates. :robots_disallowed is the one code
  # the funnel acts on rather than merely reports — the fetch is refused, so the
  # screen offers the image and text adapters instead of failing.
  Input = Data.define(:kind, :image_data, :media_type, :text, :source_url, :code, :error) do
    def self.image(image_data, media_type:, source_url: nil)
      new(kind: :image, image_data: image_data, media_type: media_type, source_url: source_url)
    end

    def self.text(text, source_url: nil)
      new(kind: :text, text: text, source_url: source_url)
    end

    def self.failure(code, error) = new(code: code, error: error)

    def initialize(kind: nil, image_data: nil, media_type: nil, text: nil,
                   source_url: nil, code: nil, error: nil)
      super
    end

    def ok? = error.nil?
    def image? = kind == :image
  end
end
