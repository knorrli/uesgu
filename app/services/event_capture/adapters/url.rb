module EventCapture
  module Adapters
    # A pasted link, fetched server-side by SafeFetch and handed on as whichever of
    # the other two inputs it turned out to be — a page becomes text, a directly
    # linked poster becomes an image. Both keep the URL: per decision 10 a capture
    # has one url column, and where the paste is the venue's own event page that is
    # exactly the key the scraper will later upsert on.
    #
    # The adapter's real target is a house show, a one-page venue site, a WhatsApp
    # link — places with no robots.txt or an unconsidered CMS default. An assessed,
    # robots-blocking venue is the rare case, and it is the one that falls back to
    # the other two adapters rather than failing.
    module Url
      module_function

      def call(url, fetcher: SafeFetch)
        return Input.failure(:url_empty, "no URL to fetch") if url.blank?

        response = fetcher.call(url)
        return Input.failure(response.code, response.error) unless response.ok?

        if SafeFetch::IMAGE_TYPES.include?(response.content_type)
          Image.call(response.body, source_url: response.url)
        else
          Text.call(text_from(response), source_url: response.url)
        end
      end

      def text_from(response)
        return response.body if response.content_type == "text/plain"

        HtmlText.call(response.body)
      end
    end
  end
end
