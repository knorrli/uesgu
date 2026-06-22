# PWA cold-start & splash screen — investigation + proposal

> Status: **investigation + proposal**. Addresses the `BACKLOG.md` item *"Slow
> PWA start / splash screen — cold start is sluggish; no splash handling yet."*
> See memory `project-pwa-install-affordance`.
>
> **Implemented (2026-06-22):** A (font preload), B (`theme-color` meta), C
> (service-worker app-shell cache), E (font subset: Phosphor.woff2 147 KB → 3.5
> KB via `script/subset_phosphor.py`). D (CSS minify) **declined** — it needs a
> build step we don't want. **Still open:** iOS `apple-touch-startup-image`
> splash images (the headline "no splash on iOS" fix — needs artwork generation),
> and the optional CSS-class trim for `phosphor.css`.

## TL;DR — two separate problems

1. **No splash on iOS.** Android already gets an auto-generated splash from the
   manifest. iOS standalone PWAs do **not** — they need explicit
   `apple-touch-startup-image` link tags or they launch to a blank screen. We
   have none. *This is the entire "no splash handling" half of the ticket, and
   it's iOS-only.*
2. **Sluggish cold start.** A serial network waterfall with no caching: full
   HTML → ~205 KB render-blocking CSS → late-discovered 147 KB icon font → many
   unbundled importmap JS modules, with the service worker caching **nothing**
   and the landing page opting out of Turbo's snapshot cache.

## Current setup (verified)

| Concern | Location |
|---|---|
| Routes | `config/routes.rb:19-22` (`rails/pwa#manifest`, `#service_worker`) |
| Manifest | `app/views/pwa/manifest.json.erb` |
| Service worker | `app/views/pwa/service-worker.js` (push-only) |
| SW registration | `app/javascript/application.js:7-11` |
| Layout head | `app/views/layouts/application.html.erb:9-31` |

Manifest is healthy: `name`/`short_name` "üsgu", `display: standalone`,
`theme_color`/`background_color` `#17131a`, icons 192 + 512 + 512-maskable
(cache-busted by `ICON_VERSION`). **Android splash needs nothing more.**

## Problem 1 — splash (iOS)

Findings:

- **No `apple-touch-startup-image` tags anywhere** (grep: zero hits). → iOS
  launches to a blank/background-color screen until first paint. Primary cause.
- **No `<meta name="theme-color">`** — only the manifest has `theme_color`, but
  iOS reads the meta tag, not the manifest, for status-bar tint. Adds to the
  unbranded launch feel.
- Present and fine: `apple-mobile-web-app-capable`, `mobile-web-app-capable`,
  `apple-touch-icon` (layout lines 10-11, 31) — install + home-screen icon work.

Fix (low risk, no design judgment beyond picking the splash artwork):

1. Add `<meta name="theme-color" content="#17131a">` (and optionally
   `apple-mobile-web-app-status-bar-style` + `apple-mobile-web-app-title`).
2. Generate per-device `apple-touch-startup-image` PNGs (centered logo on
   `#17131a`, one per modern iPhone/iPad resolution × orientation) and emit the
   `<link rel="apple-touch-startup-image" media="…">` tags. This is the only
   piece that needs artwork generation; the device/media-query matrix is
   well-known boilerplate. Masters live with the other icons (see
   `project-logo-favicon-pwa-icons`); reuse `ICON_VERSION` cache-busting.

This is shippable without much judgment — it's a known recipe — but it touches
visual launch experience, so per the "proposal only" scope I've left it for your
go-ahead rather than committing generated PNGs overnight.

## Problem 2 — sluggish cold start

The first paint of `events#index` is a serial waterfall with no caching layer:

1. **Service worker caches nothing** — `service-worker.js:46` is a deliberate
   no-op `fetch` handler (online-first by design; the comment says it only
   exists to satisfy installability). So every cold start is full-network, and a
   slow/flaky connection shows blank until the HTML lands.
2. **147 KB `Phosphor.woff2` not preloaded** — discovered only *after* the big
   CSS parses, so it's a late serial fetch + an icon flash on the header glyphs
   (theme toggle, install, bell).
3. **~205 KB single render-blocking CSS bundle** — propshaft concatenates *all*
   of `app/assets/stylesheets` with no minification; dominated by the
   un-minified `phosphor.css` (78 KB glyph map) + `events-filter.css` (22 KB) +
   `events-list.css` (18 KB). Loaded on first paint of every page.
4. **No `preload`/`preconnect`, no CDN/`asset_host`** (commented out in
   `config/environments/production.rb:47`). Fingerprinted assets *do* cache after
   first load (`max-age=1.year`, prod.rb:44) — the pain is purely the first hit.
5. **Feed opts out of Turbo snapshot cache** — `events/index.html.erb:8` sets
   `turbo-cache-control: no-cache` (to avoid list↔calendar flicker), so
   re-entering the app always re-renders rather than showing a cached snapshot.

### Proposed fixes, ranked by impact ÷ effort

| # | Fix | Effort | Notes |
|---|---|---|---|
| A | **Preload `Phosphor.woff2`** (`<link rel="preload" as="font" crossorigin>`) | tiny | Kills the late-font serial fetch + icon flash. Highest ROI. |
| B | **Add `<meta name="theme-color">`** | tiny | Branded launch; pairs with Problem 1. |
| C | **App-shell precache in the service worker** — cache CSS/JS/font + a shell on `install`, serve cache-first for those, network-first for HTML | medium | Biggest cold-start win, but it **changes the "online-first, cache nothing" stance** — a deliberate product decision (see the SW comment). Needs your sign-off + a cache-bust/versioning story. |
| D | **Minify CSS** (or at least the Phosphor glyph CSS) | small–medium | Propshaft doesn't minify; would need a build step or a pre-minified vendored `phosphor.min.css`. ~205 KB → meaningfully smaller. |
| E | **Subset the Phosphor font** to the glyphs we actually use | medium | 147 KB → a few KB if we use a dozen icons. Biggest single byte win, but adds a font-subsetting build step + the maintenance burden of regenerating when we add an icon. |
| F | **Reconsider the feed's `turbo-cache-control: no-cache`** | small | Only helps *re-entry*, not true cold start; and it's there for a real reason (flicker). Probably leave as-is. |

### Recommendation

- **Ship A + B now** — both are tiny, zero-judgment, pure wins (font preload +
  theme-color meta). These are the safe overnight-shippable changes; I've held
  off only because the PWA scope you picked was "proposal only."
- **C (SW app-shell cache)** is the real cold-start fix but is a product
  decision (it reverses the explicit online-first stance), so it needs your
  call.
- **D/E (CSS minify + font subset)** are the byte-size wins; E is the largest but
  carries ongoing maintenance. Worth doing once the above are in.
- **F**: leave the no-cache as-is — it earns its keep.

## What I'd do first, given the go-ahead

1. A + B (font preload + theme-color) — 10-minute, safe.
2. Generate iOS startup images + tags (Problem 1) — the "no splash" headline fix.
3. Then decide on C (SW caching) and E (font subset) as the structural cold-start
   work.
