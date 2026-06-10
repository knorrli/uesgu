import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="theme" on the header toggle button.
//
// Stores the user's *preference* (system | light | dark) in localStorage and
// resolves it to a concrete light|dark value on <html data-theme>. "system"
// follows the OS via prefers-color-scheme and re-resolves live when it changes.
// The pre-paint resolution lives inline in the <head> to avoid a flash of the
// wrong theme on first load; this controller keeps the button label in sync and
// handles clicks.
const ORDER = ["system", "light", "dark"]
const LABELS = { system: "Auto", light: "Light", dark: "Dark" }
// Phosphor glyphs (sit on the ph base class on the icon span).
const ICONS = { system: "ph-circle-half-tilt", light: "ph-sun", dark: "ph-moon" }
const KEY = "theme"

export default class extends Controller {
  static targets = ["label", "icon"]

  connect() {
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.onMediaChange = () => { if (this.preference === "system") this.apply() }
    this.media.addEventListener("change", this.onMediaChange)
    this.apply()
    this.render()
  }

  disconnect() {
    this.media.removeEventListener("change", this.onMediaChange)
  }

  get preference() {
    // localStorage can throw (Safari private mode, storage disabled) — fall back
    // to "system" so the toggle keeps working in-memory rather than dying.
    try {
      return localStorage.getItem(KEY) || "system"
    } catch {
      return "system"
    }
  }

  set preference(value) {
    try {
      localStorage.setItem(KEY, value)
    } catch {
      // Storage unavailable; the choice just won't persist across reloads.
    }
  }

  // Advance system → light → dark → system.
  cycle() {
    this.preference = ORDER[(ORDER.indexOf(this.preference) + 1) % ORDER.length]
    this.apply()
    this.render()
  }

  // Resolve the preference to a concrete theme on <html>.
  apply() {
    const dark = this.preference === "dark" ||
      (this.preference === "system" && this.media.matches)
    document.documentElement.dataset.theme = dark ? "dark" : "light"
  }

  render() {
    const label = LABELS[this.preference]
    if (this.hasLabelTarget) this.labelTarget.textContent = label
    if (this.hasIconTarget) {
      this.iconTarget.className = `ph ${ICONS[this.preference]}`
    }
    this.element.title = `Theme: ${label}`
    this.element.setAttribute("aria-label", `Theme: ${label} (click to change)`)
  }
}
