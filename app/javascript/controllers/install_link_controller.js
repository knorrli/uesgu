import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="install-link" on the header "Install app" link.
//
// The link ships hidden (no show-then-hide flicker) and is revealed only where
// installing the PWA is actually possible. It stays hidden when:
//  - already running as an installed PWA (standalone display mode), or
//  - on Firefox desktop, which removed PWA install entirely.
// Everywhere else can install — mobile, Chromium desktop, Safari desktop — so
// the link appears. (Desktop is no longer excluded: Chrome/Edge install PWAs as
// desktop apps, which is exactly where this used to wrongly hide it.)
export default class extends Controller {
  connect() {
    if (this.#canInstall) this.element.hidden = false
  }

  get #canInstall() {
    return !this.#isStandalone && !this.#isFirefoxDesktop
  }

  get #isStandalone() {
    return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
  }

  // Firefox desktop only — Firefox on Android/iOS can add to the home screen.
  get #isFirefoxDesktop() {
    const ua = window.navigator.userAgent
    return /firefox/i.test(ua) && !/android|fxios/i.test(ua)
  }
}
