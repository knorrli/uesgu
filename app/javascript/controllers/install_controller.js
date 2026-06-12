import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="install"
//
// "Install as app" affordance. The block is hidden by default and only revealed
// where install is actually possible — so browsers that can't install a PWA
// (e.g. Firefox desktop) show nothing instead of a dangling, dead hint.
// Behaviour is unavoidably platform-split:
//  - Chrome/Edge (Android + desktop) fire `beforeinstallprompt`; we capture it,
//    reveal the block, and drive the native install dialog from our button.
//  - iOS Safari has no programmatic install, so we reveal the block with a short
//    "Share → Add to Home Screen" hint.
//  - Already-installed (standalone) and can't-install browsers stay hidden.
export default class extends Controller {
  static targets = ["button", "iosHint"]

  connect() {
    this.deferredPrompt = null

    // Already installed → nothing to offer; stays hidden.
    if (this.#isStandalone) return

    // iOS can't install programmatically; reveal the manual steps.
    if (this.#isIos) {
      this.element.hidden = false
      if (this.hasIosHintTarget) this.iosHintTarget.hidden = false
      return
    }

    // Chromium: wait for the install event, then reveal. Browsers that never
    // fire it (Firefox desktop, …) leave the block hidden.
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
  // the block + our button instead of the browser's mini-infobar.
  capture(event) {
    event.preventDefault()
    this.deferredPrompt = event
    this.element.hidden = false
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
    this.element.hidden = true
    this.deferredPrompt = null
  }

  get #isStandalone() {
    return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
  }

  // iPadOS 13+ reports a desktop ("MacIntel") UA, so also treat a touch-capable
  // Mac as iOS.
  get #isIos() {
    return /iphone|ipad|ipod/i.test(window.navigator.userAgent) ||
      (window.navigator.platform === "MacIntel" && window.navigator.maxTouchPoints > 1)
  }
}
