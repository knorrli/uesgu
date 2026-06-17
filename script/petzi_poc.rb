# frozen_string_literal: true

# PROOF OF CONCEPT — not wired into the app. Run with: ruby script/petzi_poc.rb
#
# Demonstrates that the PETZI federation agenda (petzi.ch) is a clean, uniform,
# robots-allowed, server-rendered source covering ~15 of our venues, exposing
# date + DOORS/SHOW clock time + curated genre tags from a single schema.
#
# Pipeline mirrors what a real Scrapers::Petzi (template-method Agent) would do:
#   1. fetch the EN sitemap.xml -> enumerate every /events/ URL (one per show)
#   2. filter to our target venues by URL slug
#   3. fetch each detail page (server-rendered HTML, no JS) and extract fields
#
# Politeness: one event per venue, sequential, honest uesgu/1.0 UA, robots on.

require 'mechanize'

SITEMAP = 'https://www.petzi.ch/en/sitemap.xml'

# PETZI member venues that are on our roster, keyed by the slug fragment PETZI
# uses in its event URLs (…/events/{id}-{venue-slug}-{title-slug}/).
TARGET_VENUES = {
  'dachstock'           => 'Dachstock (Bern)',
  'isc'                 => 'ISC (Bern)',
  'kairo'               => 'Café Kairo (Bern)',
  'gaskessel'           => 'Gaskessel (Bern)',
  'kulturfabrik-kofmehl' => 'Kofmehl (Solothurn)',
  'fri-son'             => 'Fri-Son (Fribourg)',
  'bad-bonn'            => 'Bad Bonn (Düdingen)',
  'sedel'               => 'Sedel (Luzern)',
  'rote-fabrik'         => 'Rote Fabrik (Zürich)',
  'kiff'                => 'KIFF (Aarau)'
}.freeze

def agent
  @agent ||= Mechanize.new do |a|
    a.user_agent = 'uesgu/1.0'
    a.robots = true
    a.open_timeout = 15
    a.read_timeout = 20
  end
end

def squish(str) = str.to_s.gsub(/\s+/, ' ').strip

# "Malevolence / 17.06.2026 / Kulturfabrik Kofmehl - Solothurn / PETZI"
def parse_title_bar(text)
  parts = squish(text).split(' / ')
  date = parts.find { |p| p =~ %r{\A\d{2}\.\d{2}\.\d{4}\z} }
  venue_city = parts[2]
  { date: date, venue_city: venue_city }
end

def extract(page)
  doc = page.parser
  title = squish(doc.at_css('h1')&.text)
  bar = parse_title_bar(doc.at_css('title')&.text)
  body = squish(doc.text)
  doors = body[/Doors open at:\s*(\d{1,2}[:.]\d{2})/i, 1]
  show  = body[/Event starts at:\s*(\d{1,2}[:.]\d{2})/i, 1]
  genres = doc.css('a.tag').map { |a| squish(a.text) }.reject(&:empty?).uniq
  { title: title, date: bar[:date], venue_city: bar[:venue_city],
    doors: doors, show: show, genres: genres }
end

puts "Fetching sitemap: #{SITEMAP}"
sitemap = agent.get(SITEMAP)
xml = Nokogiri::XML(sitemap.body)
xml.remove_namespaces!
event_urls = xml.css('loc').map(&:text).grep(%r{/events/})
puts "  -> #{event_urls.size} event URLs enumerated\n\n"

TARGET_VENUES.each do |slug, label|
  url = event_urls.find { |u| u.include?("-#{slug}-") }
  unless url
    puts "#{label}\n  (no upcoming event matched slug '#{slug}')\n\n"
    next
  end

  begin
    data = extract(agent.get(url))
    puts "#{label}"
    puts "  title : #{data[:title]}"
    puts "  date  : #{data[:date]}"
    puts "  venue : #{data[:venue_city]}"
    puts "  doors : #{data[:doors] || '—'}    show: #{data[:show] || '—'}"
    puts "  genres: #{data[:genres].join(', ')}"
    puts "  url   : #{url}"
    puts
  rescue StandardError => e
    puts "#{label}\n  ERROR: #{e.class}: #{e.message}\n\n"
  end
end

puts 'Done. (POC only — nothing persisted.)'
