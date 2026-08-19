require "test_helper"

class EventCapture::HtmlTextTest < ActiveSupport::TestCase
  test "the title survives and script/style content does not" do
    text = EventCapture::HtmlText.call(<<~HTML)
      <html><head><title>Konzerte — ZAR</title><style>.a{color:red}</style></head>
      <body><script>var x = "Fake Concert";</script><h1>Zorpcore</h1><p>Sa 22. August, 20:00</p></body></html>
    HTML

    assert_match "Konzerte — ZAR", text
    assert_match "Zorpcore", text
    assert_match "Sa 22. August, 20:00", text
    refute_match "Fake Concert", text
    refute_match "color:red", text
  end

  # Generated markup indents everything; collapsing that must not join the lines,
  # because the break is most of what separates a date from the heading above it.
  test "indentation collapses but line structure survives" do
    text = EventCapture::HtmlText.call("<body><p>Zorpcore</p>\n\n\n      <p>Sa 22. August</p></body>")

    assert_equal "Zorpcore\n\nSa 22. August", text
  end

# Every minified page. Nokogiri's #text concatenates, so without a break put back
# at the block boundary the model is handed "ZorpcoreSa 22. August" — a title and
# a date fused into one token, which is exactly what the date parser cannot
# recover from.
test "block boundaries with no whitespace still separate" do
  text = EventCapture::HtmlText.call(
    "<body><h1>Zorpcore</h1><p>Sa 22. August</p><ul><li>20:00</li><li>ZAR, Bern</li></ul></body>"
  )

  assert_equal "Zorpcore\nSa 22. August\n20:00\nZAR, Bern", text
end

test "a <br> is a line break, not nothing" do
  assert_equal "Sa 22. August\n20:00", EventCapture::HtmlText.call("<body>Sa 22. August<br>20:00</body>")
end
end
