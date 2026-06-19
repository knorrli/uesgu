# Desktop list-view screenshots for the de-green + active-filter UI pass. Drives
# the running dev server (port 3199) with Ferrum, logs in as the disposable
# `shotbot` fixture, and captures the list at REST (no filter) plus with a style
# and a genre applied — so the resting calm vs. the green "applied" state and the
# underlined event title are all visible side by side. Output: tmp/shots-filter/.
require "ferrum"
require "fileutils"

BASE = "http://localhost:3199"
OUT  = File.expand_path("../tmp/shots-filter", __dir__)
FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

# window_size in the ctor is NOT the layout viewport (stays ~500px) — must resize.
b = Ferrum::Browser.new(headless: true, window_size: [1300, 1400], timeout: 20, process_timeout: 30)
b.resize(width: 1300, height: 1400)

b.goto("#{BASE}/session/new")
b.at_css("input[name='username']").focus.type("shotbot")
b.at_css("input[name='password']").focus.type("shotpass123")
b.at_css("input[type='submit'], button[type='submit']").click
b.network.wait_for_idle(timeout: 10) rescue nil

# Light/cream theme — the real ship surface (binary `theme` cookie, see layout).
b.cookies.set(name: "theme", value: "light", domain: "localhost", path: "/")

SHOTS = {
  "list-rest"        => "/?view=list",
  "list-style-rock"  => "/?view=list&s[]=Rock", # STYLE filter (the ♫ chip): Rock-family descriptors light
  "list-match-rock"  => "/?view=list&q[]=Rock"   # freetext: Rock / Punk Rock / Alternative Rock light
}

SHOTS.each do |slug, path|
  b.goto("#{BASE}#{path}")
  b.network.wait_for_idle(timeout: 10) rescue nil
  sleep 0.4
  b.screenshot(path: File.join(OUT, "#{slug}.png"), full: false)
  puts slug
end

# The What dropdown open, showing genre suggestions alongside the curated styles.
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
