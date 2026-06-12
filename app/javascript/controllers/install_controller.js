import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="install"
//
// "Install as app" affordance. Behaviour is unavoidably platform-split:
//  - Chrome/Edge (Android + desktop) fire `beforeinstallprompt`; we capture it
//    and drive the native install dialog from our own button — basically
//    one-click.
//  - iOS Safari has no programmatic install, so we instead reveal a short
//    "Share → Add to Home Screen" hint.
//  - Already-installed (standalone) sessions hide the whole thing.
export default class extends Controller {
  static targets = ["button", "iosHint"]

  connect() {
    this.deferredPrompt = null

    if (this.#isStandalone) {
      this.element.hidden = true
      return
    }

    if (this.#isIos) {
      if (this.hasIosHintTarget) this.iosHintTarget.hidden = false
      return
    }

    this.capture = this.capture.bind(this)
    this.installed = this.installed.bind(this)
    window.addEventListener("beforeinstallprompt", this.capture)
    window.addEventListener("appinstalled", this.installed)
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.capture)
    window.removeEventListener("appinstalled", this.installed)
  }

  // Chrome fires this when the app is installable. Stash the event and reveal
  // our button instead of letting the browser show its mini-infobar.
  capture(event) {
    event.preventDefault()
    this.deferredPrompt = event
    if (this.hasButtonTarget) this.buttonTarget.hidden = false
  }

  async install() {
    if (!this.deferredPrompt) return
    this.deferredPrompt.prompt()
    await this.deferredPrompt.userChoice
    this.deferredPrompt = null
    if (this.hasButtonTarget) this.buttonTarget.hidden = true
  }

  installed() {
    if (this.hasButtonTarget) this.buttonTarget.hidden = true
  }

  get #isStandalone() {
    return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
  }

  get #isIos() {
    return /iphone|ipad|ipod/i.test(window.navigator.userAgent) && !window.MSStream
  }
}
