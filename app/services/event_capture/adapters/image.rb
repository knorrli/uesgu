module EventCapture
  module Adapters
    # A photographed poster, a flyer, a screenshot. The media type is sniffed from
    # the bytes rather than taken from a filename or a browser-supplied
    # content-type: both are caller-controlled, and a wrong type goes into the data
    # URL and comes back as "unreadable image" rather than as an error anyone can
    # act on.
    #
    # Nothing here writes the bytes anywhere (decision 9). They are held for the one
    # request and dropped.
    module Image
      # The four the provider reads, by their magic bytes. WebP is the only one
      # needing two probes — "RIFF" alone is also AVI and WAV.
      SIGNATURES = {
        "image/png" => ->(data) { data.start_with?("\x89PNG\r\n\x1A\n".b) },
        "image/jpeg" => ->(data) { data.start_with?("\xFF\xD8\xFF".b) },
        "image/gif" => ->(data) { data.start_with?("GIF87a".b, "GIF89a".b) },
        "image/webp" => ->(data) { data.start_with?("RIFF".b) && data.byteslice(8, 4) == "WEBP".b }
      }.freeze

      # An iPhone photo taken with the default camera setting. Safari converts HEIC
      # to JPEG when the file goes through an <input type="file">, so this is the
      # AirDropped-then-uploaded path rather than the common one — but it is a whole
      # class of image arriving with a name a human can act on ("re-save as JPEG"),
      # which is worth more than one more unsupported_image.
      HEIF_BRANDS = %w[heic heix hevc hevx mif1 msf1].freeze

      # Deliberately not a downscale. There is no image library in the bundle and no
      # vips/ImageMagick on Render's native runtime, so the long-edge cap the
      # bake-off did with `sips` cannot be reproduced server-side; the verify screen
      # resizes on the client instead, where the browser already holds the pixels
      # and the upload gets cheaper too (see the design doc, "Image size").
      # This is the backstop for what arrives anyway: base64 inflates by ~4/3, and
      # one Puma worker with three threads on a starter instance holds every byte of
      # it in memory at once.
      LIMIT = 8.megabytes

      module_function

      def call(data, source_url: nil)
        data = data.to_s.b
        return Input.failure(:image_empty, "no image data") if data.empty?
        return Input.failure(:image_too_large, "image is over #{LIMIT / 1.megabyte}MB") if data.bytesize > LIMIT

        media_type = media_type_for(data)
        return Input.failure(:image_unsupported, unsupported(data)) unless media_type

        Input.image(data, media_type: media_type, source_url: source_url)
      end

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
