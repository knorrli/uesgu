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
}
