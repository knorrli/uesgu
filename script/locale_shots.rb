require "ferrum"
require "fileutils"

BASE   = "http://localhost:3199"
WIDTH  = 390
HEIGHT = 844
OUT    = File.expand_path("../tmp/shots", __dir__)
FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

LOCALES = {
  "de" => "de-CH,de;q=0.9",
  "en" => "en-US,en;q=0.9",
  "fr" => "fr-CH,fr;q=0.9"
}

PAGES = [
  ["home-list",     "/?view=list",                            false],
  ["home-calendar", "/?view=calendar&start_date=2026-06-26",  false],
  ["settings",      "/settings",                              true],
  ["favorites",     "/favorites",                             true],
  ["notifications", "/notifications",                         false],
  ["saved",         "/saved_events",                          false],
  ["rules-new",     "/notification_rules/new",                true],
  ["install",       "/install",                               true]
]

def login(browser)
  browser.goto("#{BASE}/session/new")
  browser.at_css("input[name='username']").focus.type("shotbot")
  browser.at_css("input[name='password']").focus.type("shotpass123")
  browser.at_css("input[type='submit'], button[type='submit']").click
  browser.network.wait_for_idle(timeout: 10) rescue nil
end

browser = Ferrum::Browser.new(
  headless: true,
  window_size: [WIDTH, HEIGHT],
  timeout: 20,
  process_timeout: 30
)

LOCALES.each do |code, header|
  browser.headers.set("Accept-Language" => header)
  login(browser)
  PAGES.each do |slug, path, also_full|
    begin
      browser.goto("#{BASE}#{path}")
    rescue Ferrum::StatusError => e
      puts "  skip #{code} #{slug}: #{e.message}"
      next
    end
    browser.network.wait_for_idle(timeout: 10) rescue nil
    sleep 0.4
    browser.screenshot(path: File.join(OUT, "#{slug}__#{code}.png"), full: false)
    browser.screenshot(path: File.join(OUT, "#{slug}__#{code}__full.png"), full: true) if also_full
    puts "#{code} #{slug}"
  end
  browser.cookies.clear
end

browser.quit
puts "DONE -> #{OUT}"
