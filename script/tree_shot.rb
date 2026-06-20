# One-off: screenshot the admin genre-tree view from the dev DB so we can eyeball
# the cultivation + spacing. Drives the running dev server (port 3199) with
# Ferrum, logs in as the disposable `shotbot` fixture (temporarily made admin by
# the caller), resizes to a desktop viewport (ctor window_size does NOT set the
# layout viewport — must resize), and captures the full page.
require 'ferrum'
require 'fileutils'

BASE = 'http://localhost:3199'
OUT  = File.expand_path('../tmp/shots', __dir__)
FileUtils.mkdir_p(OUT)

browser = Ferrum::Browser.new(headless: true, timeout: 20, process_timeout: 30)
browser.resize(width: 1000, height: 1200)

browser.goto("#{BASE}/session/new")
browser.at_css("input[name='username']").focus.type('shotbot')
browser.at_css("input[name='password']").focus.type('shotpass123')
browser.at_css("input[type='submit'], button[type='submit']").click
browser.network.wait_for_idle(timeout: 10) rescue nil

browser.goto("#{BASE}/admin/genres/tree")
browser.network.wait_for_idle(timeout: 10) rescue nil
sleep 0.4
path = File.join(OUT, 'genre_tree.png')
browser.screenshot(path: path, full: true)
puts "wrote #{path}"
browser.quit
