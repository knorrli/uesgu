#!/usr/bin/env ruby
# frozen_string_literal: true

# THE üsgu app-icon pipeline — one command regenerates EVERY icon artifact from
# the single source of truth below (geometry + the two palettes). There is one
# canonical mark; the only theme split is the email digest (light + dark), which
# is the one surface that sits on the mail client's own background.
#
#   ruby script/generate_icons.rb
#
# Edit the icon = edit GEOMETRY / PALETTES here, then re-run. Everything else
# (favicon, PWA icons, apple-touch, iOS splash + its <link> partial, the two
# email rasters, and the ICON_VERSION cache-bust token) is derived. No file under
# public/ that this script writes should ever be hand-edited.
#
# Needs: rsvg-convert (faithful gradient/opacity render at exact px — ImageMagick's
# own SVG path mangles the light-cone gradients to black) + ImageMagick `magick`
# (compose splash, build .ico, resize).

require "fileutils"
require "tmpdir"
require "digest"

ROOT     = File.expand_path("..", __dir__)
PUBLIC   = File.join(ROOT, "public")
SPLASH   = File.join(PUBLIC, "splash")
PARTIAL  = File.join(ROOT, "app/views/layouts/_ios_splash_screens.html.erb")
VERSION_RB = File.join(ROOT, "config/initializers/icon_version.rb")

# ── THE MASTER ──────────────────────────────────────────────────────────────
# 512×512 viewBox. The mark: a blocky lowercase "ü" whose two umlaut dots are
# coloured stage-lights (rose left, green right) casting asymmetric "party
# spotlight" cones — short stubby rose + long raking green — with rounded pool
# ends (a quadratic-curved base, not a sliced straight line).
ROSE_DOT  = [186, 140]
GREEN_DOT = [326, 140]
DOT_R     = 34

# Letterform rects: [x, y, w, h] (rx = 13 on all).
LETTER = [
  [151, 199,  70, 207],  # left stem
  [291, 199,  70, 207],  # right stem
  [151, 336, 210,  70]   # bottom bar
].freeze

# Each cone: [b1x, b1y, b2x, b2y, bulge]. Apex = its dot; the bottom edge is a
# quadratic curve bulging `bulge` px past the base midpoint → a rounded light pool.
ROSE_CONE  = [44, 470, 176, 500, 30].freeze
GREEN_CONE = [296, 500, 512, 452, 40].freeze

PALETTES = {
  dark:  { bg: "#17131a", letter: "#d4ced3", rose: "#ec6f98", green: "#38c08a", top: ".82", bot: ".05" },
  cream: { bg: "#e8e1cd", letter: "#17131a", rose: "#c2185b", green: "#0e7a4a", top: ".58", bot: ".03" }
}.freeze

BG = PALETTES[:dark][:bg] # splash canvas = brand plum, seamless splash→app hand-off

def cone(dot, c, fill)
  ax, ay = dot
  b1x, b1y, b2x, b2y, bulge = c
  cx = ((b1x + b2x) / 2.0).round
  cy = ((b1y + b2y) / 2.0 + bulge).round
  %(<path d="M #{ax},#{ay} L #{b1x},#{b1y} Q #{cx},#{cy} #{b2x},#{b2y} Z" fill="#{fill}"/>)
end

def svg_markup(key)
  p = PALETTES.fetch(key)
  letters = LETTER.map { |x, y, w, h| %(<rect x="#{x}" y="#{y}" width="#{w}" height="#{h}" rx="13" fill="#{p[:letter]}"/>) }
  <<~SVG
    <svg viewBox="0 0 512 512" width="512" height="512" xmlns="http://www.w3.org/2000/svg"><defs>
    <linearGradient id="bR" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#{p[:rose]}" stop-opacity="#{p[:top]}"/><stop offset="1" stop-color="#{p[:rose]}" stop-opacity="#{p[:bot]}"/></linearGradient>
    <linearGradient id="bG" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#{p[:green]}" stop-opacity="#{p[:top]}"/><stop offset="1" stop-color="#{p[:green]}" stop-opacity="#{p[:bot]}"/></linearGradient>
    </defs><rect width="512" height="512" fill="#{p[:bg]}"/>#{cone(ROSE_DOT, ROSE_CONE, 'url(#bR)')}#{cone(GREEN_DOT, GREEN_CONE, 'url(#bG)')}#{letters.join}<circle cx="#{ROSE_DOT[0]}" cy="#{ROSE_DOT[1]}" r="#{DOT_R}" fill="#{p[:rose]}"/><circle cx="#{GREEN_DOT[0]}" cy="#{GREEN_DOT[1]}" r="#{DOT_R}" fill="#{p[:green]}"/></svg>
  SVG
end

# iOS splash device matrix (portrait-only; app is portrait-locked). Deduped by
# physical resolution → one image covers every device sharing it. Uncovered
# devices fall back to a blank launch (no regression). Add a row for new Apple
# screen sizes and re-run.
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
MARK_FRACTION = 0.62 # mark bounding box as fraction of the shorter screen edge

# ── tooling guards ──────────────────────────────────────────────────────────
abort "`rsvg-convert` not found on PATH" if `which rsvg-convert`.strip.empty?
abort "`magick` (ImageMagick) not found on PATH" if `which magick`.strip.empty?

FileUtils.mkdir_p(SPLASH)

def render_png(svg_path, size, out)
  ok = system("rsvg-convert", "-w", size.to_s, "-h", size.to_s, svg_path, "-o", out)
  abort "rsvg-convert failed: #{out}" unless ok
end

Dir.mktmpdir("usgu-icons") do |tmp|
  dark_svg  = File.join(tmp, "dark.svg")
  cream_svg = File.join(tmp, "cream.svg")
  File.write(dark_svg,  svg_markup(:dark))
  File.write(cream_svg, svg_markup(:cream))

  # 1. canonical SVG — served as the favicon AND the human-viewable master.
  File.write(File.join(PUBLIC, "icon.svg"), svg_markup(:dark))
  puts "icon.svg               canonical mark (served favicon + master)"

  # 2. dark raster set — favicon.ico (16+32), apple-touch (180), PWA (192 + 512).
  ico16 = File.join(tmp, "ico16.png"); render_png(dark_svg, 16, ico16)
  ico32 = File.join(tmp, "ico32.png"); render_png(dark_svg, 32, ico32)
  abort "magick .ico failed" unless system("magick", ico16, ico32, File.join(PUBLIC, "favicon.ico"))
  puts "favicon.ico            16 + 32"

  { "apple-touch-icon.png" => 180, "icon-192.png" => 192, "icon.png" => 512 }.each do |name, size|
    render_png(dark_svg, size, File.join(PUBLIC, name))
    puts format("%-22s %d", name, size)
  end

  # 3. email pair — the one theme split. light = cream ground, dark = plum ground.
  render_png(cream_svg, 192, File.join(PUBLIC, "email-icon-light.png"))
  render_png(dark_svg,  192, File.join(PUBLIC, "email-icon-dark.png"))
  puts "email-icon-{light,dark}.png  192 (cream / plum)"

  # 4. iOS splash — dark mark centred on the brand canvas + the <link> partial.
  mark_tmp = File.join(tmp, "splash-mark.png")
  seen = {}
  DEVICES.each do |label, css_w, css_h, ratio|
    pw, ph = css_w * ratio, css_h * ratio
    next if seen[[pw, ph]]

    mark_px = ([css_w, css_h].min * ratio * MARK_FRACTION).round
    render_png(dark_svg, mark_px, mark_tmp)
    ok = system("magick", "-size", "#{pw}x#{ph}", "xc:#{BG}", mark_tmp,
                "-gravity", "center", "-composite", "-depth", "8", "-strip",
                File.join(SPLASH, "launch-#{pw}x#{ph}.png"))
    abort "splash compose failed for #{label}" unless ok
    seen[[pw, ph]] = true
  end
  puts "splash/launch-*.png    #{seen.size} unique device images"

  emitted = {}
  links = DEVICES.filter_map do |_l, css_w, css_h, ratio|
    pw, ph = css_w * ratio, css_h * ratio
    next if emitted[[pw, ph]]

    emitted[[pw, ph]] = true
    media = "(device-width: #{css_w}px) and (device-height: #{css_h}px) and " \
            "(-webkit-device-pixel-ratio: #{ratio}) and (orientation: portrait)"
    %(<link rel="apple-touch-startup-image" media="#{media}" ) +
      %(href="/splash/launch-#{pw}x#{ph}.png?v=<%= ICON_VERSION %>">)
  end
  header = <<~ERB
    <%# GENERATED by script/generate_icons.rb — do not edit by hand.
        iOS PWA splash screens (apple-touch-startup-image). Each media query must
        match a device exactly or iOS ignores it; uncovered devices launch blank
        (no regression). Re-run the script after changing the device list. %>
  ERB
  File.write(PARTIAL, header + links.join("\n") + "\n")
  puts "_ios_splash_screens.html.erb  #{emitted.size} <link> tags"

  # 5. ICON_VERSION — content hash of both masters, so the cache-bust token
  #    changes iff the art changes. Deterministic; never a forgotten manual bump.
  digest = Digest::SHA256.hexdigest(svg_markup(:dark) + svg_markup(:cream))[0, 8]
  File.write(VERSION_RB, <<~RB)
    # GENERATED by script/generate_icons.rb — do not edit by hand.
    #
    # Cache-busting token appended (?v=) to favicon / app-icon / splash URLs. It is
    # a content hash of the icon masters, so it changes exactly when the art does —
    # forcing browsers (and iOS, which caches the home-screen icon hard by URL) to
    # refetch instead of serving a stale icon. A plain top-level constant so both
    # the layout and the PWA manifest view (rendered outside ApplicationController)
    # can read it.
    ICON_VERSION = "#{digest}".freeze
  RB
  puts "icon_version.rb        ICON_VERSION = #{digest}"
end

puts "\nDone. All icon artifacts regenerated from one master."
