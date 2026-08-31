module EventCapture
  module Adapters
    module Image
      SIGNATURES = {
        "image/png" => ->(data) { data.start_with?("\x89PNG\r\n\x1A\n".b) },
        "image/jpeg" => ->(data) { data.start_with?("\xFF\xD8\xFF".b) },
        "image/gif" => ->(data) { data.start_with?("GIF87a".b, "GIF89a".b) },
        "image/webp" => ->(data) { data.start_with?("RIFF".b) && data.byteslice(8, 4) == "WEBP".b }
      }.freeze

      HEIF_BRANDS = %w[heic heix hevc hevx mif1 msf1].freeze

      LIMIT = 8.megabytes

      module_function

      def call(data)
        data = data.to_s.b
        return Input.failure(:image_empty, "no image data") if data.empty?
        return too_large if data.bytesize > LIMIT

        media_type = media_type_for(data)
        return Input.failure(:image_unsupported, unsupported(data)) unless media_type

        Input.image(data, media_type: media_type)
      end

      def too_large = Input.failure(:image_too_large, "image is over #{LIMIT / 1.megabyte}MB")

      def media_type_for(data)
        SIGNATURES.find { |_type, matches| matches.call(data) }&.first
      end

      def unsupported(data)
        return "HEIC/HEIF images are not readable — re-save it as JPEG or PNG" if heif?(data)

        "not a PNG, JPEG, WebP or GIF"
      end

      def heif?(data) = data.byteslice(4, 4) == "ftyp".b && HEIF_BRANDS.include?(data.byteslice(8, 4))
    end
  end
end
