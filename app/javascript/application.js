// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Work around a Turbo Drive scroll bug. A turbo-frame navigation with
// data-turbo-action="advance" — we use one for the calendar's linkable open-day
// URL (app/views/events/_calendar.html.erb) — promotes to a page-level visit that
// updates history WITHOUT re-rendering the page. That no-render path sets the page
// View's internal `forceReloaded` flag, and Turbo only ever clears it on a full
// page load. While it's set, Turbo skips its scroll reset (performScroll), so any
// later Drive visit — e.g. clicking "next" on the feed — silently stops scrolling
// to the top (it stays put / drifts to the new page's clamped bottom).
//
// `forceReloaded` is read in exactly one spot (the scroll skip), so clearing it is
// side-effect-free: it just lets advance visits scroll to top and restore visits
// restore, as intended. We reset before each render so a stale frame promotion
// can't poison the next navigation. Optional chaining keeps this a no-op (reverting
// to stock behaviour) if a future Turbo reshapes these internals.
document.addEventListener("turbo:before-render", () => {
  const view = window.Turbo?.session?.view
  if (view) view.forceReloaded = false
})

// Register the service worker that powers Web Push + installability. Served at
// /service-worker (config/routes.rb) so its scope is the whole site.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker
    .register("/service-worker", { scope: "/" })
    .catch((error) => console.error("Service worker registration failed:", error))

  // Deep-link from a tapped push notification while this window is already open. The
  // service worker (app/views/pwa/service-worker.js, navigateLiveClient) can't safely
  // navigate us itself on iOS, so it asks us to do it: we ACK on the message port so
  // it knows we're alive (and won't also openWindow), then visit the target. ACK
  // first — the visit may tear this page down before a later postMessage would land.
  navigator.serviceWorker.addEventListener("message", (event) => {
    if (event.data?.type !== "navigate") return
    event.ports[0]?.postMessage("ok")
    if (window.Turbo) {
      window.Turbo.visit(event.data.url)
    } else {
      window.location.href = event.data.url
    }
  })
}
