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

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      // Prefer focusing a tab already on the target path.
      for (const client of clientList) {
        if (new URL(client.url).pathname === path && "focus" in client) {
          return client.focus()
        }
      }
      // Otherwise focus any open tab and navigate it, or open a fresh window.
      if (clientList.length > 0 && "navigate" in clientList[0]) {
        return clientList[0].focus().then((client) => client.navigate(path))
      }
      if (clients.openWindow) return clients.openWindow(path)
    })
  )
})

// A no-op fetch handler. We don't cache anything (the app is online-first), but
// registering a fetch listener satisfies some browsers' PWA installability
// criteria. Not calling respondWith() lets every request hit the network as
// normal.
self.addEventListener("fetch", () => {})
