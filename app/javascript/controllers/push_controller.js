import { Controller } from "@hotwired/stimulus"

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

  async #refresh() {
    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.getSubscription()
    const denied = Notification.permission === "denied"
    const state = denied ? "denied" : subscription ? "on" : "off"

    this.statusTarget.hidden = !denied
    if (denied) this.statusTarget.textContent = this.statusDeniedValue
    this.buttonTarget.textContent = subscription ? this.labelOnValue : this.labelOffValue
    this.buttonTarget.dataset.state = state
    this.buttonTarget.disabled = denied

    if (this.hasTestButtonTarget) this.testButtonTarget.hidden = !subscription
  }

  get #supported() {
    return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
  }

  get #isStandalone() {
    return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
  }

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

  #urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
    const raw = atob(base64)
    return Uint8Array.from(raw, (char) => char.charCodeAt(0))
  }

  #show(el) { if (el) el.hidden = false }
  #hide(el) { if (el) el.hidden = true }
}
