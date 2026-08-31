require "ferrum"
require "fileutils"

BASE = "http://localhost:3199"
OUT  = File.expand_path("../tmp/shots-sheets", __dir__)
FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

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

b.goto("#{BASE}/?view=list")
shoot(b, "01-bar-rest")

b.goto("#{BASE}/?view=list&s[]=Rock&q[]=metal")
shoot(b, "02-bar-applied")

def open_sheet(b, field)
  b.at_css(".filter-trigger[data-filter-sheets-field-param='#{field}']")&.click
  sleep 0.45
end

b.goto("#{BASE}/?view=list&s[]=Rock&q[]=metal")
b.network.wait_for_idle(timeout: 10) rescue nil
open_sheet(b, "what")
b.screenshot(path: File.join(OUT, "03-what-open.png"))
puts "03-what-open"

b.goto("#{BASE}/?view=list")
b.network.wait_for_idle(timeout: 10) rescue nil
open_sheet(b, "where")
b.screenshot(path: File.join(OUT, "04-where-open.png"))
puts "04-where-open"

b.goto("#{BASE}/?view=list")
b.network.wait_for_idle(timeout: 10) rescue nil
open_sheet(b, "when")
b.screenshot(path: File.join(OUT, "05-when-open.png"))
puts "05-when-open"

b.quit
puts "DONE -> #{OUT}"
