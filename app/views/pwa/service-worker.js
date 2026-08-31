self.addEventListener("push", (event) => {
  if (!event.data) return

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
      for (const client of clientList) {
        if (new URL(client.url).pathname === path && "focus" in client) return client.focus()
      }
      if (clients.openWindow) return clients.openWindow(url)
    })
  )
})

const CACHE_VERSION = "v1"
const ASSET_CACHE = `usgu-assets-${CACHE_VERSION}`

self.addEventListener("install", () => {
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
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

  const isAsset =
    request.method === "GET" &&
    url.origin === self.location.origin &&
    url.pathname.startsWith("/assets/")
  if (!isAsset) return

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
