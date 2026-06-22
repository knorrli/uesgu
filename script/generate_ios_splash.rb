#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate iOS PWA splash screens (apple-touch-startup-image).
#
# Why: Android derives a launch splash from the manifest, but iOS standalone PWAs
# show a blank screen unless we supply one PNG per device — sized to that device's
# exact physical resolution — plus a <link> tag whose media query matches the
# device precisely. This is the source of truth + the regenerate mechanism.
#
#   ruby script/generate_ios_splash.rb
#
# Needs ImageMagick (`magick`). It:
#   1. writes one PNG per device into public/splash/ (the üsgu mark centred on the
#      #17131a brand background — the same colour as theme-color/manifest, so the
#      splash → app hand-off is seamless), and
#   2. (re)writes the link-tag partial app/views/layouts/_ios_splash_screens.html.erb,
#      which the layout renders in <head>.
#
# DEVICES is portrait-only (the app is portrait-locked in the manifest) and
# deduped by (width, height, ratio) — one image covers every device that shares a
# resolution. Devices we don't list simply fall back to a blank launch (today's
# behaviour), so partial coverage is always safe. Add a row when Apple ships a new
# screen size and re-run.

require "fileutils"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
MARK = File.join(ROOT, "public/icon.svg")
OUT_DIR = File.join(ROOT, "public/splash")
PARTIAL = File.join(ROOT, "app/views/layouts/_ios_splash_screens.html.erb")

# Fraction of the shorter screen edge the mark's *bounding box* spans. The glyph
# only fills part of its square viewBox (the rest is padding + faint light-cones),
# so the visible logo reads noticeably smaller than this number — keep it generous.
MARK_FRACTION = 0.62
BG = "#17131a"

# label, CSS width, CSS height (portrait points), device-pixel-ratio.
DEVICES = [
  ["iPhone SE / 8",                         375,  667, 2],
  ["iPhone XR / 11",                        414,  896, 2],
  ["iPhone X / XS / 11 Pro",                375,  812, 3],
  ["iPhone XS Max / 11 Pro Max",            414,  896, 3],
  ["iPhone 12 mini / 13 mini",              360,  780, 3],
  ["iPhone 12 / 13 / 14 / 16e",             390,  844, 3],
  ["iPhone 12/13 Pro Max / 14 Plus",        428,  926, 3],
  ["iPhone 14 Pro / 15 / 15 Pro / 16",      393,  852, 3],
  ["iPhone 14 Pro Max / 15 Plus / 16 Plus", 430,  932, 3],
  ["iPhone 16 Pro",                         402,  874, 3],
  ["iPhone 16 Pro Max",                     440,  956, 3],
  ["iPad mini 6",                           744, 1133, 2],
  ["iPad 9.7 / 10.2",                       768, 1024, 2],
  ["iPad 10th gen",                         820, 1180, 2],
  ["iPad Air / Pro 10.5",                   834, 1112, 2],
  ["iPad Air / Pro 11",                     834, 1194, 2],
  ["iPad Pro 12.9",                        1024, 1366, 2],
  ["iPad Pro 13 (M4)",                     1032, 1376, 2]
].freeze

def filename(phys_w, phys_h) = "launch-#{phys_w}x#{phys_h}.png"

def media_query(css_w, css_h, ratio)
  "(device-width: #{css_w}px) and (device-height: #{css_h}px) and " \
    "(-webkit-device-pixel-ratio: #{ratio}) and (orientation: portrait)"
end

abort "missing mark: #{MARK}" unless File.exist?(MARK)
abort "ImageMagick `magick` not found on PATH" if `which magick`.strip.empty?
# rsvg-convert (librsvg) renders the gradient/opacity faithfully and at exact
# pixels — ImageMagick's own SVG path mangles the light-cone gradients to black.
abort "`rsvg-convert` not found on PATH" if `which rsvg-convert`.strip.empty?

FileUtils.mkdir_p(OUT_DIR)
mark_tmp = File.join(Dir.tmpdir, "usgu-splash-mark.png")

# Dedupe by physical resolution so shared sizes produce one image + one link.
seen = {}
DEVICES.each do |label, css_w, css_h, ratio|
  phys_w = css_w * ratio
  phys_h = css_h * ratio
  png = File.join(OUT_DIR, filename(phys_w, phys_h))

  unless seen[[phys_w, phys_h]]
    mark_px = ([css_w, css_h].min * ratio * MARK_FRACTION).round
    # 1. rasterise the square mark crisply at the target size.
    ok = system("rsvg-convert", "-w", mark_px.to_s, "-h", mark_px.to_s, MARK, "-o", mark_tmp)
    abort "rsvg-convert failed for #{label}" unless ok
    # 2. centre it on the brand-colour canvas.
    ok = system(
      "magick", "-size", "#{phys_w}x#{phys_h}", "xc:#{BG}",
      mark_tmp, "-gravity", "center", "-composite", "-depth", "8", "-strip", png
    )
    abort "magick composite failed for #{label} (#{phys_w}x#{phys_h})" unless ok
    seen[[phys_w, phys_h]] = true
    puts format("  %-40s %4d x %-4d  ->  %s", label, phys_w, phys_h, File.basename(png))
  end
end

# Emit the link-tag partial. Deduped by resolution; ICON_VERSION cache-busts at
# request time exactly like the other icons in the layout.
emitted = {}
lines = DEVICES.filter_map do |_label, css_w, css_h, ratio|
  phys_w = css_w * ratio
  phys_h = css_h * ratio
  key = [phys_w, phys_h]
  next if emitted[key]

  emitted[key] = true
  %(<link rel="apple-touch-startup-image" ) +
    %(media="#{media_query(css_w, css_h, ratio)}" ) +
    %(href="/splash/#{filename(phys_w, phys_h)}?v=<%= ICON_VERSION %>">)
end

header = <<~ERB
  <%# GENERATED by script/generate_ios_splash.rb — do not edit by hand.
      iOS PWA splash screens (apple-touch-startup-image). Each tag's media query
      must match a device exactly or iOS ignores it; uncovered devices launch
      blank (no regression). Re-run the script after changing the device list. %>
ERB

File.write(PARTIAL, header + lines.join("\n") + "\n")
puts "\nwrote #{DEVICES.size} devices -> #{emitted.size} unique splash images"
puts "wrote partial #{PARTIAL.sub("#{ROOT}/", "")}"
