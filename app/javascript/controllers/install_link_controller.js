import { Controller } from "@hotwired/stimulus"

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

  get #isFirefoxDesktop() {
    const ua = window.navigator.userAgent
    return /firefox/i.test(ua) && !/android|fxios/i.test(ua)
  }
}
