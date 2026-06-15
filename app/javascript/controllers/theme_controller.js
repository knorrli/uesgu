import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="theme" on the header toggle button.
//
// Binary light ↔ dark, stored in a `theme` cookie (per-device) so the SERVER can
// render <html data-theme> and the matching favicon up-front — no flash. The
// first-visit default (no cookie yet) is resolved from the OS inline in <head>.
// This controller only handles the click and keeps the button icon/label in
// sync; it no longer follows the OS live (that was the old "system" preference,
// now dropped).
const LABELS = { light: "Light", dark: "Dark" }
const ICONS = { light: "ph-sun", dark: "ph-moon" }
const ONE_YEAR = 60 * 60 * 24 * 365

export default class extends Controller {
  static targets = ["label", "icon"]

  connect() {
    this.render()
  }

  // The cookie is the source of truth; fall back to whatever the inline head
  // script resolved onto <html> (covers the click before a cookie round-trips).
  get theme() {
    const m = document.cookie.match(/(?:^|;\s*)theme=(light|dark)/)
    if (m) return m[1]
    return document.documentElement.dataset.theme === "dark" ? "dark" : "light"
  }

  set theme(value) {
    document.cookie = `theme=${value};path=/;max-age=${ONE_YEAR};samesite=lax`
  }

  toggle() {
    const next = this.theme === "dark" ? "light" : "dark"
    this.theme = next
    document.documentElement.dataset.theme = next
    const favicon = document.getElementById("favicon-svg")
    if (favicon) favicon.href = next === "light" ? "/icon-light.svg" : "/icon.svg"
    this.render()
  }

  render() {
    const t = this.theme
    if (this.hasLabelTarget) this.labelTarget.textContent = LABELS[t]
    if (this.hasIconTarget) this.iconTarget.className = `ph ${ICONS[t]}`
    this.element.title = `Theme: ${LABELS[t]}`
    this.element.setAttribute("aria-label", `Theme: ${LABELS[t]} (click to change)`)
  }
}
