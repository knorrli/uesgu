import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="push"
//
// Per-device Web Push opt-in toggle (settings page). Reflects the live browser
// state — subscribed / not / permission-denied / unsupported — and on toggle
// either subscribes (asking OS permission, then registering with our backend)
// or unsubscribes (removing it both sides). The server stays authoritative; this
// just keeps the button honest about *this* device.
export default class extends Controller {
  static targets = ["button", "status", "unsupported", "installFirst", "testButton"]
  static values = {
    vapidPublicKey: String,
    labelOn: String,
    labelOff: String,
    statusDenied: String
  }

  connect() {
    if (this.#supported) {
      this.#refresh()
      return
    }

    // Push isn't available. On iOS that's because the Push API is exposed only
    // to an installed home-screen app — so point the user at installing first
    // rather than the dead-end "unsupported" message. Everywhere else it's a
    // browser that genuinely lacks the Push API.
    this.#hide(this.buttonTarget)
    if (this.#isIos && !this.#isStandalone && this.hasInstallFirstTarget) {
      this.#show(this.installFirstTarget)
    } else {
      this.#show(this.unsupportedTarget)
    }
  }

  async toggle() {
    this.buttonTarget.disabled = true
    try {
      const registration = await navigator.serviceWorker.ready
      const existing = await registration.pushManager.getSubscription()
      if (existing) {
        await this.#unsubscribe(existing)
      } else {
        await this.#subscribe(registration)
      }
    } catch (error) {
      console.error("Push toggle failed:", error)
    } finally {
      this.buttonTarget.disabled = false
      this.#refresh()
    }
  }

  async #subscribe(registration) {
    const permission = await Notification.requestPermission()
    if (permission !== "granted") return

    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.#urlBase64ToUint8Array(this.vapidPublicKeyValue)
    })

    await this.#send("POST", { subscription: subscription.toJSON() })
  }

  async #unsubscribe(subscription) {
    await this.#send("DELETE", { endpoint: subscription.endpoint })
    await subscription.unsubscribe()
  }

  // Send a push to *this* device so the user can confirm it actually arrives.
  async sendTest() {
    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.getSubscription()
    if (!subscription) return

    this.testButtonTarget.disabled = true
    try {
      await this.#send("POST", { endpoint: subscription.endpoint }, "/push_subscriptions/test")
    } catch (error) {
      console.error("Test push failed:", error)
    } finally {
      this.testButtonTarget.disabled = false
    }
  }

  // Paint the button + status from the current browser state.
  async #refresh() {
    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.getSubscription()
    const denied = Notification.permission === "denied"
    const state = denied ? "denied" : subscription ? "on" : "off"

    // On/off is already legible in the button label, so only surface a status line
    // for "denied" — the one state the button (disabled, still reading "activate")
    // can't explain on its own.
    this.statusTarget.hidden = !denied
    if (denied) this.statusTarget.textContent = this.statusDeniedValue
    this.buttonTarget.textContent = subscription ? this.labelOnValue : this.labelOffValue
    this.buttonTarget.dataset.state = state
    this.buttonTarget.disabled = denied

    // The test button only makes sense once this device is actually subscribed.
    if (this.hasTestButtonTarget) this.testButtonTarget.hidden = !subscription
  }

  get #supported() {
    return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
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

  async #send(method, body, path = "/push_subscriptions") {
    const response = await fetch(path, {
      method,
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify(body)
    })
    if (!response.ok) throw new Error(`push_subscriptions ${method} failed: ${response.status}`)
  }

  // VAPID keys travel as URL-safe base64; the Push API wants a Uint8Array.
  #urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
    const raw = atob(base64)
    return Uint8Array.from(raw, (char) => char.charCodeAt(0))
  }

  #show(el) { if (el) el.hidden = false }
  #hide(el) { if (el) el.hidden = true }
}
