// Service worker for üsgu's installable PWA.
//
// Two jobs:
//  1. Receive Web Push messages and show them as OS notifications.
//  2. On notification click, focus an existing tab on the target path or open one.
//
// The push payload is the JSON our backend sends (PushSubscription#deliver):
//   { title, options: { body, icon, badge, data: { path } } }

// ⚠️ TEMPORARY DIAGNOSTIC. Bump on every deploy so we can see — ON THE DEVICE —
// which service worker is actually active: it's stamped into every notification we
// show (push) and into the DEBUG report (notificationclick). Remove with the rest of
// the diagnostic scaffolding.
const SW_BUILD = "D3"

self.addEventListener("push", (event) => {
  if (!event.data) return

  const { title, options } = event.data.json()
  options.body = `${options.body || ""} · build ${SW_BUILD}`
  event.waitUntil(self.registration.showNotification(title, options))
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()

  const path = event.notification.data?.path || "/"
  const url = new URL(path, self.location.origin).href

  event.waitUntil(onClick(path, url))
})

// ⚠️ TEMPORARY DIAGNOSTIC BUILD. Two-part probe of how iOS runs notificationclick:
//
//  • "CLICK D3" notification — fired FIRST, before any other async work. If you see
//    it, the handler fires. If you DON'T, iOS isn't dispatching notificationclick at
//    all (or kills the SW before even this runs).
//  • "DEBUG D3" notification — fired LAST, after matchAll + navigation attempts. If
//    CLICK shows but DEBUG doesn't, the SW is being killed mid-async as the app
//    foregrounds (so we can't rely on async work inside the handler).
//
// Candidate fix folded in: we postMessage every client a {type:"navigate"} the moment
// the handler runs. That message QUEUES on a suspended page and is delivered when iOS
// resumes it on foreground, so the page navigates ITSELF (Turbo.visit in
// application.js) without the SW having to stay alive. This survives the kill above.
async function onClick(path, url) {
  // (1) Prove the handler fired, before anything else can be cut short.
  await self.registration.showNotification(`CLICK ${SW_BUILD}`, {
    body: "notificationclick fired",
    tag: "usgu-click",
    data: { path: "/" }
  }).catch(() => {})

  // (2) Attempt the deep-link and gather diagnostics.
  const log = []
  try {
    const clientList = await clients.matchAll({ type: "window", includeUncontrolled: true })
    log.push(`clients=${clientList.length}`)
    clientList.forEach((c, i) => log.push(`#${i} ${pathOf(c)} foc=${c.focused} vis=${c.visibilityState}`))

    // Queue a self-navigate on every page (delivered when iOS resumes it).
    for (const client of clientList) {
      client.postMessage({ type: "navigate", path, url })
    }

    // Belt-and-suspenders: focus + WindowClient.navigate() too.
    for (const client of clientList) {
      if ("focus" in client) { try { await client.focus() } catch (e) {} }
      if ("navigate" in client) {
        try { await client.navigate(url); log.push("nav=ok") } catch (e) { log.push("nav=ERR:" + (e && e.message)) }
      }
    }

    if (!clientList.length && clients.openWindow) {
      log.push("openWindow")
      await clients.openWindow(url)
    }
  } catch (e) {
    log.push("FATAL:" + (e && e.message))
  }
  await report(log)
}

function pathOf(client) {
  try { return new URL(client.url).pathname } catch (e) { return "?" }
}

function report(log) {
  return self.registration.showNotification(`DEBUG ${SW_BUILD}`, {
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
