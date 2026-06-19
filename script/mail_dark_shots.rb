# Screenshots the digest email preview in both color schemes by emulating
# prefers-color-scheme via CDP — faithful to how WebKit-based mail clients
# (Apple Mail, new Outlook for Mac, iOS Mail) resolve the media query.
# Loads the raw HTML part (not the preview chrome). Output: tmp/mail/<scheme>.png
require "ferrum"
require "fileutils"

URL = "http://localhost:3199/rails/mailers/notification_mailer/digest?part=text%2Fhtml"
OUT = File.expand_path("../tmp/mail", __dir__)
FileUtils.mkdir_p(OUT)

browser = Ferrum::Browser.new(headless: true, window_size: [760, 1400], timeout: 20, process_timeout: 30)
browser.resize(width: 760, height: 1400)

%w[light dark].each do |scheme|
  browser.page.command("Emulation.setEmulatedMedia",
    features: [{ name: "prefers-color-scheme", value: scheme }])
  browser.goto(URL)
  browser.network.wait_for_idle(timeout: 10) rescue nil
  sleep 0.4
  browser.screenshot(path: File.join(OUT, "#{scheme}.png"), full: true)
  puts "#{scheme} -> #{File.join(OUT, "#{scheme}.png")}"
end

browser.quit
puts "DONE"
