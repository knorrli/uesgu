// Service worker for üsgu's installable PWA.
//
// Push is split by platform:
//  • iOS 18.4+ uses Declarative Web Push — the push PAYLOAD (PushSubscription#deliver)
//    carries the notification and a `navigate` URL, and the OS shows it and deep-links
//    on tap with no JavaScript. This is essential: iOS does NOT fire notificationclick
//    for an already-running standalone PWA, so nothing in this file can deep-link there.
//  • Browsers that don't understand the declarative payload (Chrome/Android, desktop)
//    ignore its `web_push: 8030` key and fire the push event below instead; we read the
//    same payload, show the notification, and deep-link from notificationclick — which
//    DOES fire on those platforms.

self.addEventListener("push", (event) => {
  if (!event.data) return

  // Declarative shape: { web_push: 8030, notification: { title, body, navigate } }.
  const notification = event.data.json().notification || {}
  let path = "/"
  try { path = new URL(notification.navigate, self.location.origin).pathname } catch (e) {}

  event.waitUntil(
    self.registration.showNotification(notification.title || "üsgu", {
      body: notification.body,
      icon: "/icon.png",
      badge: "/icon.png",
      data: { path }
    })
  )
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()

  const path = event.notification.data?.path || "/"
  const url = new URL(path, self.location.origin).href

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      // Focus a tab already on the target path, else open one. (Not reached on iOS —
      // see the header note — but correct for Chrome/Android/desktop.)
      for (const client of clientList) {
        if (new URL(client.url).pathname === path && "focus" in client) return client.focus()
      }
      if (clients.openWindow) return clients.openWindow(url)
    })
  )
})

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
