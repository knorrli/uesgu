import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="install"
//
// "Install as app" affordance. Unlike a hide-when-impossible block, this always
// shows *something* actionable — installing is the single most important step for
// our users, so every browser gets either a one-tap button or concrete steps.
// Behaviour is unavoidably platform-split:
//  - Already installed (standalone): a short "you're all set" confirmation.
//  - Chrome/Edge (Android + desktop) fire `beforeinstallprompt`; we capture it
//    and drive the native install dialog from our own button.
//  - iOS Safari has no programmatic install → "Share → Add to Home Screen" steps.
//  - Firefox (Android + desktop) doesn't fire the event → menu steps.
//  - Anything else → generic browser-menu steps as a safe fallback.
export default class extends Controller {
  static targets = ["button", "installed", "ios", "firefox", "generic"]

  connect() {
    this.deferredPrompt = null

    // Already installed → reassure, and tell the page (so e.g. the header link
    // can hide itself).
    if (this.#isStandalone) {
      this.#show("installed")
      return
    }

    // iOS can't install programmatically; reveal the manual steps.
    if (this.#isIos) {
      this.#show("ios")
      return
    }

    // Firefox never fires beforeinstallprompt; reveal its menu steps.
    if (this.#isFirefox) {
      this.#show("firefox")
      return
    }

    // Chromium & everything else: show generic menu steps right away so the
    // page is never empty, then upgrade to the one-tap button if the browser
    // offers a native prompt.
    this.#show("generic")
    this.capture = this.capture.bind(this)
    this.installed = this.installed.bind(this)
    window.addEventListener("beforeinstallprompt", this.capture)
    window.addEventListener("appinstalled", this.installed)
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.capture)
    window.removeEventListener("appinstalled", this.installed)
  }

  // Chrome fires this when the app is installable: swap the generic steps for our
  // own one-tap button instead of the browser's mini-infobar.
  capture(event) {
    event.preventDefault()
    this.deferredPrompt = event
    this.#hide("generic")
    this.#show("button")
  }

  async install() {
    if (!this.deferredPrompt) return
    this.deferredPrompt.prompt()
    await this.deferredPrompt.userChoice
    this.deferredPrompt = null
    this.#hide("button")
  }

  installed() {
    ;["button", "ios", "firefox", "generic"].forEach((t) => this.#hide(t))
    this.#show("installed")
    this.deferredPrompt = null
  }

  #show(name) {
    const target = `${name}Target`
    if (this[`has${name[0].toUpperCase()}${name.slice(1)}Target`]) this[target].hidden = false
  }

  #hide(name) {
    const target = `${name}Target`
    if (this[`has${name[0].toUpperCase()}${name.slice(1)}Target`]) this[target].hidden = true
  }

  get #isStandalone() {
    return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
  }

  get #isFirefox() {
    return /firefox|fxios/i.test(window.navigator.userAgent)
  }

  // iPadOS 13+ reports a desktop ("MacIntel") UA, so also treat a touch-capable
  // Mac as iOS.
  get #isIos() {
    return /iphone|ipad|ipod/i.test(window.navigator.userAgent) ||
      (window.navigator.platform === "MacIntel" && window.navigator.maxTouchPoints > 1)
  }
}
