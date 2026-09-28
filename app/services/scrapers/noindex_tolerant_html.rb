module Scrapers
  # With robots on, Mechanize discards any page whose <meta name="robots"> says
  # noindex, after downloading it. noindex restricts search indexing, not
  # fetching; robots.txt and nofollow stay enforced by Mechanize.
  class NoindexTolerantHtml < Nokogiri::HTML::Document
    def noindex?(*) = false
  end
end
