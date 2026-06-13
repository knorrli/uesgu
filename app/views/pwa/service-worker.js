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

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      // Prefer focusing a tab already sitting on the target path.
      for (const client of clientList) {
        if (new URL(client.url).pathname === path && "focus" in client) {
          return client.focus()
        }
      }
      // Otherwise open the target. We deliberately do NOT use WindowClient.navigate():
      // on iOS, a standalone PWA has a single window whose web-content process iOS
      // suspends/evicts when backgrounded. The service worker still holds a stale
      // WindowClient for it, and navigate() resurrects the window chrome without
      // reloading the dead process — the blank white screen. openWindow() forces a
      // real load (and on iOS standalone reuses the one window rather than spawning).
      if (clients.openWindow) return clients.openWindow(url)
    })
  )
})

// A no-op fetch handler. We don't cache anything (the app is online-first), but
// registering a fetch listener satisfies some browsers' PWA installability
// criteria. Not calling respondWith() lets every request hit the network as
// normal.
self.addEventListener("fetch", () => {})
