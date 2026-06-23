// Service worker for üsgu's installable PWA.
//
// Two jobs:
//  1. Receive Web Push messages and show them as OS notifications.
//  2. On notification click, focus an existing tab on the target path or open one.
//
// The push payload is the JSON our backend sends (PushSubscription#deliver):
//   { title, options: { body, icon, badge, data: { path } } }

self.addEventListener("push", (event) => {
  if (!event.data) return

  const { title, options } = event.data.json()
  event.waitUntil(self.registration.showNotification(title, options))
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()

  const path = event.notification.data?.path || "/"
  const url = new URL(path, self.location.origin).href

  event.waitUntil(diagnoseAndOpen(path, url))
})

// ⚠️ TEMPORARY DIAGNOSTIC BUILD. Reports what notificationclick decides via a "DEBUG"
// notification, and tries WindowClient.navigate() as the candidate deep-link fix.
// Once we know how iOS actually behaves, revert this to the clean handler.
//
// Reading the DEBUG body: it lists how many window clients matchAll() saw (and each
// one's path / focused / visibility), then which branch ran (act=focus-exact /
// navigate / openWindow) and whether navigate() succeeded. If you see NO debug
// notification at all when you tap, notificationclick never fired (or the new SW
// isn't active) — that's the most important signal.
async function diagnoseAndOpen(path, url) {
  const log = []
  try {
    const clientList = await clients.matchAll({ type: "window", includeUncontrolled: true })
    log.push(`clients=${clientList.length}`)
    clientList.forEach((c, i) => log.push(`#${i} ${pathOf(c)} foc=${c.focused} vis=${c.visibilityState}`))

    // 1) A window is already on the target path — just focus it.
    for (const client of clientList) {
      if (pathOf(client) === path && "focus" in client) {
        log.push("act=focus-exact")
        await report(log)
        return client.focus()
      }
    }

    // 2) A window exists on another path — try to navigate IT (the candidate fix).
    for (const client of clientList) {
      if ("navigate" in client) {
        log.push("act=navigate")
        try {
          const navigated = await client.navigate(url)
          log.push("navigate=ok")
          await report(log)
          return navigated && "focus" in navigated ? navigated.focus() : undefined
        } catch (e) {
          log.push("navigate=ERR:" + (e && e.message))
        }
      }
    }

    // 3) Nothing to navigate — open fresh.
    log.push("act=openWindow")
    await report(log)
    if (clients.openWindow) return clients.openWindow(url)
  } catch (e) {
    log.push("FATAL:" + (e && e.message))
    await report(log)
  }
}

function pathOf(client) {
  try { return new URL(client.url).pathname } catch (e) { return "?" }
}

function report(log) {
  return self.registration.showNotification("DEBUG", {
    body: log.join(" | "),
    tag: "usgu-debug",
    data: { path: "/" }
  }).catch(() => {})
}

// App-shell caching. The app is online-first for *content* — HTML, API calls and
// everything cross-origin always hit the network — but the fingerprinted static
// assets (CSS / JS / fonts under /assets/) are immutable and worth serving from
// cache, which is the bulk of cold-start latency. We cache them lazily on first
// fetch; there's no precache list to keep in sync because propshaft digests the
// URLs (a byte change yields a new URL, so a cached entry can never be stale).
//
// Bump CACHE_VERSION to wipe the asset cache (e.g. if it ever grows unwieldy from
// accumulated old digests). Within a version, superseded digests are harmless.
const CACHE_VERSION = "v1"
const ASSET_CACHE = `usgu-assets-${CACHE_VERSION}`

self.addEventListener("install", () => {
  // Take over without waiting for existing tabs to close. Nothing to precache.
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      // Drop caches from older versions of this worker.
      const names = await caches.keys()
      await Promise.all(
        names.filter((name) => name !== ASSET_CACHE).map((name) => caches.delete(name))
      )
      await self.clients.claim()
    })()
  )
})

self.addEventListener("fetch", (event) => {
  const { request } = event
  const url = new URL(request.url)

  // Only intercept our own fingerprinted assets. Everything else stays
  // online-first: we don't call respondWith(), so it hits the network as normal.
  const isAsset =
    request.method === "GET" &&
    url.origin === self.location.origin &&
    url.pathname.startsWith("/assets/")
  if (!isAsset) return

  // Cache-first — safe because the URL carries a content digest.
  event.respondWith(
    caches.open(ASSET_CACHE).then(async (cache) => {
      const hit = await cache.match(request)
      if (hit) return hit

      const response = await fetch(request)
      if (response.ok) cache.put(request, response.clone())
      return response
    })
  )
})
