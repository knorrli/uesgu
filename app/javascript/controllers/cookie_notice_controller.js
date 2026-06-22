import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="cookie-notice" on the courtesy notice.
//
// The notice ships hidden. On first visit (no flag) we reveal it; once
// dismissed we remember that in localStorage — deliberately not a cookie, so the
// notice can honestly say we set exactly three cookies (login + theme + filter).
// Returning visitors never see it: it's removed before it can paint.
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
