import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="standalone"
//
// Hides its element when there's no reason to offer installation: either the
// app is already running as an installed PWA (standalone display mode), or
// we're on a desktop where a home-screen app makes little sense. Used on the
// header "Install app" link so it only shows on mobile, when there's something
// to do.
export default class extends Controller {
  connect() {
    if (this.#isStandalone || !this.#isMobile) {
      this.element.hidden = true
    }
  }

  get #isStandalone() {
    return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
  }

  // Touch-primary devices (phones/tablets) report a coarse pointer; desktops
  // with a mouse report a fine pointer. This keeps the install link off of
  // computers without sniffing user agents.
  get #isMobile() {
    return window.matchMedia("(pointer: coarse)").matches
  }
}
