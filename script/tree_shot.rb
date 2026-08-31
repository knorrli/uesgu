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
