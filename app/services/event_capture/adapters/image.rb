module EventCapture
  module Adapters
    # The media type is sniffed rather than read off a filename or a browser-supplied
    # content-type: both are caller-controlled, and a wrong one goes into the data URL
    # and comes back as "unreadable image" instead of as an error anyone can act on.
    #
    # Nothing here writes the bytes anywhere, and nothing should — decision 9.
    module Image
      # "RIFF" alone is also AVI and WAV, hence WebP's second probe.
      SIGNATURES = {
        "image/png" => ->(data) { data.start_with?("\x89PNG\r\n\x1A\n".b) },
        "image/jpeg" => ->(data) { data.start_with?("\xFF\xD8\xFF".b) },
        "image/gif" => ->(data) { data.start_with?("GIF87a".b, "GIF89a".b) },
        "image/webp" => ->(data) { data.start_with?("RIFF".b) && data.byteslice(8, 4) == "WEBP".b }
      }.freeze

      # Safari converts HEIC to JPEG through an <input type="file">, so this catches
      # the AirDropped-then-uploaded path rather than the common one. Worth naming
      # anyway: "re-save it as JPEG" is something a contributor can act on.
      HEIF_BRANDS = %w[heic heix hevc hevx mif1 msf1].freeze

      # A cap, deliberately not a downscale: there is no image library in the bundle
      # and no vips/ImageMagick on Render's native runtime, so the resize happens on
      # the client (design doc, "Image size"). Sized by memory, not by the provider —
      # base64 inflates by ~4/3 and one Puma worker holds every byte of it at once.
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

      # Callable before the bytes are read, so an upload can be refused on its
      # declared size rather than after it has been pulled into memory whole.
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
