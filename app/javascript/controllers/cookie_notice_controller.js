import { Controller } from "@hotwired/stimulus"

const KEY = "cookie_notice_seen"

export default class extends Controller {
  connect() {
    let seen = false
    try { seen = localStorage.getItem(KEY) === "1" } catch (e) {}
    if (seen) {
      this.element.remove()
    } else {
      this.element.hidden = false
      this.resizeObserver = new ResizeObserver(() => this.#reserveSpace(this.element.offsetHeight))
      this.resizeObserver.observe(this.element)
    }
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.#reserveSpace(0)
  }

  dismiss() {
    try { localStorage.setItem(KEY, "1") } catch (e) {}
    this.element.remove()
  }

  #reserveSpace(height) {
    document.documentElement.style.setProperty("--cookie-notice-clearance", `${height}px`)
  }
}
