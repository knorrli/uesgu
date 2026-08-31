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
    }
  }

  dismiss() {
    try { localStorage.setItem(KEY, "1") } catch (e) {}
    this.element.remove()
  }
}
