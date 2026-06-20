# Screenshots of the When-sheet custom-range CALENDAR (range_calendar_controller)
# on mobile (full-screen sheet, 390px) and desktop (inline dropdown panel, 1100px).
# Same harness as script/ui_sheet_shots.rb: drives the dev server on :3199, logs in
# as the disposable `shotbot` fixture, light/cream theme. Captures each width at
# rest and with a range picked. Output: tmp/shots-rangecal/.
require "ferrum"
require "fileutils"
require "date"

BASE = "http://localhost:3199"
OUT  = File.expand_path("../tmp/shots-rangecal", __dir__)
FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

# Two days in the displayed (current) month — the calendar opens on it.
START_DAY = (Date.today - Date.today.mday + 1) + 9  # the 10th
END_DAY   = (Date.today - Date.today.mday + 1) + 19 # the 20th

def login(b)
  b.goto("#{BASE}/session/new")
  b.at_css("input[name='username']").focus.type("shotbot")
  b.at_css("input[name='password']").focus.type("shotpass123")
  b.at_css("input[type='submit'], button[type='submit']").click
  b.network.wait_for_idle(timeout: 10) rescue nil
  b.cookies.set(name: "theme", value: "light", domain: "localhost", path: "/")
end

def open_when(b)
  b.goto("#{BASE}/?view=list")
  b.network.wait_for_idle(timeout: 10) rescue nil
  b.at_css(".filter-trigger[data-filter-sheets-field-param='when']")&.click
  sleep 0.45
end

def pick_range(b)
  b.at_css(".sheet[data-field=when] .range-cal__day[data-date='#{START_DAY.iso8601}']")&.click
  sleep 0.1
  b.at_css(".sheet[data-field=when] .range-cal__day[data-date='#{END_DAY.iso8601}']")&.click
  sleep 0.2
end

def scroll_cal_into_view(b)
  b.evaluate("document.querySelector('.sheet[data-field=when] .range-cal')?.scrollIntoView({block:'nearest'})")
  sleep 0.2
end

def shoot(b, slug, full: false)
  b.screenshot(path: File.join(OUT, "#{slug}.png"), full: full)
  puts slug
end

# ── Mobile (390×844): full-screen When sheet ───────────────────────────────────
b = Ferrum::Browser.new(headless: true, window_size: [390, 844], timeout: 20, process_timeout: 30)
b.resize(width: 390, height: 844)
login(b)

open_when(b)
shoot(b, "01-mobile-rest", full: true)   # full page: presets + calendar in one image
pick_range(b)
shoot(b, "02-mobile-range", full: true)
b.quit

# ── Desktop (1100×900): inline When dropdown panel ─────────────────────────────
d = Ferrum::Browser.new(headless: true, window_size: [1100, 900], timeout: 20, process_timeout: 30)
d.resize(width: 1100, height: 900)
login(d)

open_when(d)
shoot(d, "03-desktop-rest")
pick_range(d)
shoot(d, "04-desktop-range")
d.quit

puts "DONE -> #{OUT}"
