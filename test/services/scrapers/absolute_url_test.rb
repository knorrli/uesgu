require "test_helper"

class Scrapers::AbsoluteUrlTest < Minitest::Test
  BASE = "https://zorp.ch/de/programm"

  def test_characters_a_browser_would_encode_are_percent_encoded
    {
      "/de/events/zorp 420" => "https://zorp.ch/de/events/zorp%20420",
      "/de/events/blörp" => "https://zorp.ch/de/events/bl%C3%B6rp",
      "/de/events/a|b{c}" => "https://zorp.ch/de/events/a%7Cb%7Bc%7D",
      "  /de/events/grb\n" => "https://zorp.ch/de/events/grb"
    }.each { |href, expected| assert_equal expected, absolute_url(href), href.inspect }
  end

  def test_an_already_encoded_href_is_left_alone
    assert_equal "https://zorp.ch/de/events/zorp%20420?a=1&b=%C3%B6#x", absolute_url("/de/events/zorp%20420?a=1&b=%C3%B6#x")
  end

  def test_an_absolute_href_ignores_the_base
    assert_equal "https://blorp.ch/event%201", absolute_url("https://blorp.ch/event 1")
    assert_equal "https://blorp.ch/event", absolute_url("//blorp.ch/event")
  end

  def test_a_missing_href_has_no_url
    assert_nil absolute_url(nil)
    assert_nil absolute_url("  ")
  end

  private

  def absolute_url(href) = Scrapers::Agent.new.absolute_url(href, BASE)
end
