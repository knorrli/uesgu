import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="rule-name" on the alert form wrapper. The rule
// name is always derived from the filter (no custom names); this shows it as a
// live preview that rebuilds as you add/remove chips or change the window — the
// same shape the server's NotificationRule#describe produces (styles · locations
// · queries · window), so the preview matches what gets saved.
export default class extends Controller {
  static targets = ["preview"]
  static values = { fallback: String, added: String }

  connect() {
    this.refresh()
  }

  // Mirror NotificationRule#describe: <what> · [<where> ·] <window | new events>.
  refresh() {
    const what = [...this.#values("s[]"), ...this.#values("q[]")].join(", ")
    const parts = [what || this.fallbackValue]

    const where = this.#values("l[]").join(", ")
    if (where) parts.push(where)

    parts.push(this.#window() || this.addedValue)

    this.previewTarget.textContent = parts.join(" · ")
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
