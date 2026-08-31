require "ferrum"
require "fileutils"

BASE = "http://localhost:3199"
OUT  = File.expand_path("../tmp/shots-filter", __dir__)
FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

b = Ferrum::Browser.new(headless: true, window_size: [1300, 1400], timeout: 20, process_timeout: 30)
b.resize(width: 1300, height: 1400)

b.goto("#{BASE}/session/new")
b.at_css("input[name='username']").focus.type("shotbot")
b.at_css("input[name='password']").focus.type("shotpass123")
b.at_css("input[type='submit'], button[type='submit']").click
b.network.wait_for_idle(timeout: 10) rescue nil

b.cookies.set(name: "theme", value: "light", domain: "localhost", path: "/")

SHOTS = {
  "list-rest"        => "/?view=list",
  "list-style-rock"  => "/?view=list&s[]=Rock",
  "list-match-rock"  => "/?view=list&q[]=Rock"
}

SHOTS.each do |slug, path|
  b.goto("#{BASE}#{path}")
  b.network.wait_for_idle(timeout: 10) rescue nil
  sleep 0.4
  b.screenshot(path: File.join(OUT, "#{slug}.png"), full: false)
  puts slug
end

b.goto("#{BASE}/?view=list")
b.network.wait_for_idle(timeout: 10) rescue nil
input = b.at_css(".filter-desktop input[role='combobox']")
if input
  input.focus
  input.type("rock")
  sleep 0.7
  b.screenshot(path: File.join(OUT, "what-dropdown.png"))
  puts "what-dropdown"
end

b.quit
puts "DONE -> #{OUT}"
