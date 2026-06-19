# Mobile filter-SHEET screenshots (phone viewport) for the tap-to-filter parity
# pass. Same harness as script/ui_filter_shots.rb (logs in as the disposable
# `shotbot` fixture, light/cream theme) but at a PHONE viewport (<600px) so the
# What/Where/When bottom-sheets render instead of the desktop inline filter, and
# it taps a trigger open before shooting so we see the sheet itself.
# Output: tmp/shots-sheets/.
require "ferrum"
require "fileutils"

BASE = "http://localhost:3199"
OUT  = File.expand_path("../tmp/shots-sheets", __dir__)
FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

# window_size in the ctor is NOT the layout viewport (Ferrum gotcha) — must resize.
# 390×844 ≈ iPhone 12/13/14; well under the 600px sheet breakpoint.
b = Ferrum::Browser.new(headless: true, window_size: [390, 844], timeout: 20, process_timeout: 30)
b.resize(width: 390, height: 844)

b.goto("#{BASE}/session/new")
b.at_css("input[name='username']").focus.type("shotbot")
b.at_css("input[name='password']").focus.type("shotpass123")
b.at_css("input[type='submit'], button[type='submit']").click
b.network.wait_for_idle(timeout: 10) rescue nil

b.cookies.set(name: "theme", value: "light", domain: "localhost", path: "/")

def shoot(b, slug)
  b.network.wait_for_idle(timeout: 10) rescue nil
  sleep 0.4
  b.screenshot(path: File.join(OUT, "#{slug}.png"), full: false)
  puts slug
end

# 1) Mobile list at rest — the trigger bar with empty What/Where/When.
b.goto("#{BASE}/?view=list")
shoot(b, "01-bar-rest")

# 2) Trigger bar + applied-filter summary chips (a style + a freetext query).
b.goto("#{BASE}/?view=list&s[]=Rock&q[]=metal")
shoot(b, "02-bar-applied")

# Tap a trigger open and shoot the sheet. The transition is 0.22s.
def open_sheet(b, field)
  b.at_css(".filter-trigger[data-filter-sheets-field-param='#{field}']")&.click
  sleep 0.45
end

# 3) WHAT sheet — current state (styles only, no genre suggestions).
b.goto("#{BASE}/?view=list&s[]=Rock&q[]=metal")
b.network.wait_for_idle(timeout: 10) rescue nil
open_sheet(b, "what")
b.screenshot(path: File.join(OUT, "03-what-open.png"))
puts "03-what-open"

# 4) WHERE sheet — canton > city > venue tree.
b.goto("#{BASE}/?view=list")
b.network.wait_for_idle(timeout: 10) rescue nil
open_sheet(b, "where")
b.screenshot(path: File.join(OUT, "04-where-open.png"))
puts "04-where-open"

# 5) WHEN sheet — presets + custom range.
b.goto("#{BASE}/?view=list")
b.network.wait_for_idle(timeout: 10) rescue nil
open_sheet(b, "when")
b.screenshot(path: File.join(OUT, "05-when-open.png"))
puts "05-when-open"

b.quit
puts "DONE -> #{OUT}"
