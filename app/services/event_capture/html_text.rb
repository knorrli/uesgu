module EventCapture
  # A fetched page, reduced to the text a model should read. Nokogiri is already a
  # dependency (Mechanize pulls it) and no scraper-grade parsing is wanted here: the
  # extractor's whole point is that it works on pages we have written no selectors
  # for.
  #
  # Anchor hrefs are dropped along with the rest of the markup, which loses rule 6
  # ("read URLs — a venue is often identifiable only from a link"). Keeping them
  # would mean pasting every nav and footer link into the prompt to save the one in
  # the body, and the link that actually matters is already carried losslessly:
  # Input#source_url holds the URL the contributor pasted.
  module HtmlText
    STRIPPED = "script, style, noscript, template, svg, iframe, head".freeze

    # Nokogiri's #text concatenates, so a block boundary with no whitespace around it
    # — `<h1>Zorpcore</h1><p>Sa 22. August</p>`, which is every minified page — comes
    # out as "ZorpcoreSa 22. August". The break has to be put back before the text is
    # taken, or the model is handed a title and a date fused into one token.
    BLOCKS = "address, article, aside, blockquote, br, dd, div, dl, dt, figcaption, " \
             "figure, footer, form, h1, h2, h3, h4, h5, h6, header, hr, li, main, nav, " \
             "ol, p, pre, section, table, td, th, tr, ul".freeze

    module_function

    def call(html)
      doc = Nokogiri::HTML(html)
      title = doc.title
      doc.css(STRIPPED).remove
      doc.css(BLOCKS).each { |node| node.add_next_sibling(Nokogiri::XML::Text.new("\n", doc)) }

      squeeze([title, (doc.at_css("body") || doc).text].compact_blank.join("\n"))
    end

    # Collapse the indentation of generated markup without joining lines: the line
    # breaks are most of what tells a date apart from the heading above it.
    def squeeze(text)
      text.gsub(/[[:blank:] ]+/, " ").gsub(/ ?\n ?/, "\n").gsub(/\n{3,}/, "\n\n").strip
    end
  end
end
