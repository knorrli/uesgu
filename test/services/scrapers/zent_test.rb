require "test_helper"

class Scrapers::ZentTest < Minitest::Test
  CASES = {
    "5 Gänge / nur auf Reservation. Start: 18:30"      => "18:30", #
    "Türöffnung 18.30, Ausklang an der Bar"            => "18:30", #
    "Konzertbeginn: 20:00"                             => "20:00",
    "Türöffnung 19.00 / Beginn um 20.00"               => "20:00", #
    "Show 21:15"                                       => "21:15",
    "Feines vom Feuer / 75.— exkl. Getränke"           => nil,     # p
    "Start: 99:99 kaputt"                              => nil,
    ""                                                 => nil
  }.freeze

  def test_mines_start_time_from_body_prose
    CASES.each do |prose, expected|
      time = event_for(prose).start_time
      if expected
        assert_equal "2026-07-23 #{expected}", time.strftime("%Y-%m-%d %H:%M"), "prose #{prose.inspect}"
      else
        assert_equal "2026-07-23 00:00", time.strftime("%Y-%m-%d %H:%M"), "prose #{prose.inspect}"
      end
    end
  end

  private

  def event_for(prose)
    html = <<~HTML
      <article class="event-item">
        <header><time>23.07.2026</time><h2>Testabend</h2></header>
        <div class="main">#{prose}</div>
      </article>
    HTML
    row = Nokogiri::HTML.fragment(html).at_css("article")
    scraper = Scrapers::Zent.new
    Struct.new(:start_time).new(scraper.event_start_time(row))
  end
end
