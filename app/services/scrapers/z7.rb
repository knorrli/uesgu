module Scrapers
  # Z7 Konzertfabrik (Pratteln) runs WooCommerce: every show is a `product`, and
  # the home page renders the whole upcoming programme server-side inside
  # `.block-event-calendar` — one <article> per show carrying an ISO date and the
  # deep link. Clock time, blurb and genre tags exist only on the detail page,
  # so this clicks through.
  #
  # We read the GERMAN tree, not its WPML English twin: the translation ships
  # duplicate genre terms slugged `-en` ("heavy-metal-en", "goth-en"), omits the
  # shows nobody translated, and falls back to `?post_type=product&p=<id>`
  # permalinks where the German side has a real slug.
  class Z7 < Agent
    # WooCommerce prints tag SLUGS on the product wrapper and the readable names
    # nowhere on the page, so #event_genres maps them through the venue's own
    # vocabulary. 51 terms today, one page.
    TAG_VOCABULARY_URL = URI.parse("https://z-7.ch/wp-json/wp/v2/product_tag?per_page=100").freeze

    def self.url
      URI.parse("https://z-7.ch/")
    end

    # Pin the path base, not just the host: the English tree degrades untranslated
    # shows to `?post_type=product&p=<id>`, and that shape reaching event_url would
    # mean we had silently changed language tree under the scraper.
    def self.event_url_pattern
      %r{\Ahttps://z-7\.ch/event/}
    end

    def event_rows
      page.css(".block-event-calendar article")
    end

    # A row badges its hall whenever the show isn't in the main room. "Mini Z7" is
    # the small stage in the same building, but Z7 also promotes shows it merely
    # books into someone else's house ("Volkshaus Zürich"), which stands in another
    # town — carrying those under Z7's Pratteln place would file them in the wrong
    # branch of the WHERE tree, so leave them to that venue's own source. Every
    # room Z7 runs itself is branded with the venue name, which is the test.
    def skip_row?(row)
      hall = row.at_css("a span")&.text&.squish
      hall.present? && hall.exclude?("Z7")
    end

    def event_url(row)
      URI.join(self.class.url, link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    # The date comes from the list row, whose `<time datetime>` is already ISO —
    # the detail page spells it as German prose ("04. September 2026"). A festival
    # row carries a second `<time>` for its end day; the first is the start. The
    # clock time must be read by LABEL: doors ("Einlass") sits directly below the
    # start in the same shape, so taking the first time in the block would ship
    # every show an hour early.
    def event_start_time(content)
      date = current_row.at_css("time")&.[]("datetime")
      raise "Missing Z7 date for #{current_row.at_css('h2')&.text&.squish.inspect}" if date.blank?

      Time.zone.parse([date, meta_value(content, "Beginn")&.[](/\d{1,2}:\d{2}/)].compact.join(" "))
    end

    def event_title(content)
      header(content)&.at_css("h1")&.text&.squish
    end

    # Under the title sit the tour/edition line(s) and the support acts.
    def event_description(content)
      header(content)&.css("p, h4")&.map { |node| node.text.squish }&.compact_blank&.join(", ")
    end

    # WooCommerce stamps this product's tags onto its wrapper as `product_tag-<slug>`.
    # Read them from that wrapper alone — the related-events strip further down the
    # page carries OTHER shows' tags in the same shape, and a page-wide scan would
    # tag every event with its neighbours' genres.
    def event_genres(content)
      tag_slugs(content).filter_map { |slug| tag_names[slug] }
    end

    private

    def link_for(row)
      Page::Link.new(row.at_css("a"), @mech, page)
    end

    def header(content)
      content.at_css(".block-event-product-header")
    end

    def tag_slugs(content)
      content.at_css("div[id^=product-]")&.[]("class").to_s.scan(/product_tag-([a-z0-9-]+)/).flatten
    end

    # slug => the venue's own spelling, fetched once per run. A slug cannot be
    # de-slugified back into it: Z7 writes "Black/Death-Metal", "Singer/Songwriter",
    # "NDH". When the vocabulary is unreachable (or `get` returns nil, as in the
    # offline golden harness) this stays empty and the run ships no genres —
    # deliberately, because falling back to the slugs would mint "ndh" and
    # "hard-rock" as junk taxonomy that an admin then has to alias by hand.
    def tag_names
      @tag_names ||= fetch_tag_names
    end

    # Genres are a nice-to-have on top of a programme we can otherwise read in
    # full, so a vocabulary that 404s (WordPress can switch the REST API off) is
    # logged and shrugged off. Left to raise it would surface per event, failing
    # the whole venue over a supplementary fetch.
    def fetch_tag_names
      response = get(TAG_VOCABULARY_URL)
      return {} if response.blank?

      parse_json(response.body).to_h { |term| [term["slug"], term["name"]] }
    rescue Mechanize::Error => e
      Rails.logger.error("[#{self.class.location}] tag vocabulary unavailable: #{e.class}: #{e.message}")
      {}
    end

    # A labelled row of the detail page's event-info block, whose rows are
    # `<p><b>Beginn: </b> 20:00</p>`.
    def meta_value(content, label)
      row = content.css(".fooevents-meta p").find { |p| p.at_css("b")&.text&.squish&.start_with?(label) }
      row&.text&.squish
    end
  end
end
