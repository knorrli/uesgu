// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Register the service worker that powers Web Push + installability. Served at
// /service-worker (config/routes.rb) so its scope is the whole site.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker
    .register("/service-worker", { scope: "/" })
    .catch((error) => console.error("Service worker registration failed:", error))
}
