module EventCapture
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
