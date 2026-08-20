module EventCapture
  # What an adapter hands the Extractor. A failure is returned rather than raised,
  # for the same reason Extraction's is: in a bulk capture one bad input is a row to
  # retry, not a dead batch.
  #
  # `code` is a symbol because the capture screen owns the three-locale copy; `error`
  # is developer-facing English, for the rake task and the logs.
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
