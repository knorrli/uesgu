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

  event.waitUntil(openNotificationPath(path, url))
})

// Bring the PWA to `path` when a push notification is tapped. Three cases, and iOS
// standalone makes them subtle:
//
//  1. A live window is already sitting on `path` — just focus it.
//  2. A live window is on some OTHER path (e.g. the app was backgrounded on the feed)
//     — we must navigate it. iOS won't do this for us: clients.openWindow() on an
//     already-running standalone PWA only FOCUSES the single window, it does not load
//     the new URL — that's the deep-link bug this handler exists to fix. And
//     WindowClient.navigate() is unsafe: if iOS had evicted the window's web-content
//     process, navigate() resurrects the dead chrome to a blank white screen. So
//     instead we postMessage the live page and let it navigate ITSELF (location-level
//     visit), which is reliable precisely because the page is running to receive the
//     message and ACK it.
//  3. No live window — cold start, or the process was evicted and can't answer our
//     message. clients.openWindow() forces a real load (reusing the one window on iOS).
//
// We can't tell a live window from an evicted-but-still-listed one synchronously, so
// case 2 probes with a short ACK timeout and falls through to case 3 on silence.
async function openNotificationPath(path, url) {
  const clientList = await clients.matchAll({ type: "window", includeUncontrolled: true })

  for (const client of clientList) {
    if (new URL(client.url).pathname === path && "focus" in client) {
      return client.focus()
    }
  }

  for (const client of clientList) {
    if (await navigateLiveClient(client, path, url)) return
  }

  if (clients.openWindow) return clients.openWindow(url)
}

// Focus a window and ask its page to navigate itself to `url`. Resolves true only if
// the page answers within the timeout — i.e. it's genuinely alive and has taken over
// the navigation. false means "treat it as dead; let the caller fall back to
// openWindow()". The page-side listener lives in app/javascript/application.js.
function navigateLiveClient(client, path, url) {
  if (!("focus" in client) || !("postMessage" in client)) return Promise.resolve(false)

  return new Promise((resolve) => {
    const channel = new MessageChannel()
    const timer = setTimeout(() => resolve(false), 600)
    channel.port1.onmessage = () => {
      clearTimeout(timer)
      resolve(true)
    }
    client.focus()
    client.postMessage({ type: "navigate", path, url }, [channel.port2])
  })
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
