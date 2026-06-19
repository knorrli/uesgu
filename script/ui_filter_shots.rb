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

SHOTS = {
  "list-rest"          => "/?view=list",
  "list-active-style"  => "/?view=list&s[]=Metal",
  "list-active-genre"  => "/?view=list&q[]=Metal"
}

SHOTS.each do |slug, path|
  b.goto("#{BASE}#{path}")
  b.network.wait_for_idle(timeout: 10) rescue nil
  sleep 0.4
  b.screenshot(path: File.join(OUT, "#{slug}.png"), full: false)
  puts slug
end

b.quit
puts "DONE -> #{OUT}"
