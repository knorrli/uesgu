import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="install"
//
// "Install as app" affordance. Unlike a hide-when-impossible block, this always
// shows *something*: a one-tap button where we can drive a native prompt, concrete
// steps where the user can do it by hand, or — where install is genuinely
// impossible — an honest note. Behaviour is unavoidably platform-split:
//  - Already installed (standalone): a short "you're all set" confirmation.
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

    // Firefox never fires beforeinstallprompt. On Android its menu installs / adds
    // to the home screen; on desktop it can't install a PWA at all, so be honest.
    if (this.#isFirefox) {
      this.#show(this.#isAndroid ? "firefox" : "firefoxDesktop")
      return
    }

    // Desktop Safari: no prompt event either. Safari 17+ can "Add to Dock"; show
    // that rather than the wrong generic browser-menu steps.
    if (this.#isSafari) {
      this.#show("safariDesktop")
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

  // iPadOS 13+ reports a desktop ("MacIntel") UA, so also treat a touch-capable
  // Mac as iOS.
  get #isIos() {
    return /iphone|ipad|ipod/i.test(window.navigator.userAgent) ||
      (window.navigator.platform === "MacIntel" && window.navigator.maxTouchPoints > 1)
  }
}
