import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="rule-name" on the alert form wrapper. The rule
// name is always derived from the filter (no custom names); this shows it as a
// live preview that rebuilds as you add/remove chips or change the window — the
// same shape the server's NotificationRule#describe produces (styles · locations
// · queries · window), so the preview matches what gets saved.
export default class extends Controller {
  static targets = ["preview"]
  static values = { fallback: String }

  connect() {
    this.refresh()
  }

  refresh() {
    const parts = [
      this.#values("s[]").join(", "),
      this.#values("l[]").join(", "),
      this.#values("q[]").join(", "),
      this.#window()
    ].filter(Boolean)

    this.previewTarget.textContent = parts.length ? parts.join(" · ") : this.fallbackValue
  }

  #values(name) {
    return [...this.element.querySelectorAll(`input[name="${name}"]`)]
      .map((input) => input.value.trim())
      .filter(Boolean)
  }

  #window() {
    const select = this.element.querySelector("select[name='d[]']")
    return select && select.value ? select.options[select.selectedIndex].textContent.trim() : ""
  }
}
