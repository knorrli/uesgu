import { Controller } from "@hotwired/stimulus"

// What each engine actually supports, which is why the branching exists:
//  - Chrome/Edge/Chromium (Android + desktop) fire `beforeinstallprompt`; we
//    capture it and drive the native install dialog from our own button.
//  - iOS Safari: no programmatic install → "Share → Add to Home Screen" steps.
//  - Firefox Android: menu → Install / Add to Home screen.
//  - Firefox desktop: PWA install was removed years ago — can't install; say so.
//  - Safari desktop: no prompt event → "File → Add to Dock" (Safari 17+).
//  - Anything else → generic browser-menu steps as a safe fallback.
export default class extends Controller {
  static targets = ["button", "installed", "ios", "firefox", "firefoxDesktop", "safariDesktop", "generic"]

  connect() {
    this.deferredPrompt = null

    if (this.#isStandalone) {
      this.#show("installed")
      return
    }

    if (this.#isIos) {
      this.#show("ios")
      return
    }

    if (this.#isFirefox) {
      this.#show(this.#isAndroid ? "firefox" : "firefoxDesktop")
      return
    }

    if (this.#isSafari) {
      this.#show("safariDesktop")
      return
    }

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
    ;["button", "ios", "firefox", "firefoxDesktop", "safariDesktop", "generic"].forEach((t) => this.#hide(t))
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

  get #isAndroid() {
    return /android/i.test(window.navigator.userAgent)
  }

  // Desktop Safari only (iOS Safari is already caught by #isIos): matches Safari
  // but excludes the Chromium/Firefox engines whose UA also carries "Safari".
  get #isSafari() {
    const ua = window.navigator.userAgent
    return /safari/i.test(ua) && !/chrome|chromium|crios|edg|fxios|android/i.test(ua)
  }

  get #isIos() {
    return /iphone|ipad|ipod/i.test(window.navigator.userAgent) ||
      (window.navigator.platform === "MacIntel" && window.navigator.maxTouchPoints > 1)
  }
}
