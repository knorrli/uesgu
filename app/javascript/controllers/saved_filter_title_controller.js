import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="saved-filter-title" on the editor wrapper. Live-updates the
// derived title (h1) as the filter is edited, mirroring SavedFilter#describe:
//   "<genres + queries | Alle Events> · [locations] · <window | new-events>".
// Reads the picker's checked inputs (g[]/q[]/l[]) and the checked window preset
// directly, so it stays in sync without a round-trip. Display-only — the server
// re-derives the authoritative name on Save (describe), so the two never drift.
export default class extends Controller {
  static targets = ["title"]
  static values = { scopeAll: String, addedLabel: String }

  connect() {
    this.update()
  }

  // Fired on any change bubbling up from the picker (checkbox toggle, window
  // preset, a staged free-text query row — see filter-sheets#addQuery).
  update() {
    const what = [...this.#values("g"), ...this.#values("q")]
    const where = this.#values("l")

    const parts = [what.length ? what.join(", ") : this.scopeAllValue]
    if (where.length) parts.push(where.join(", "))
    parts.push(this.#temporal())

    this.titleTarget.textContent = parts.join(" · ")
  }

  // Use input VALUES (not labels) so this matches describe exactly: a g[]/l[] value
  // is the raw genre/location name, and a q[] value is the free-text string.
  #values(name) {
    return [...this.element.querySelectorAll(`input[name="${name}[]"]:checked`)].map((i) => i.value)
  }

  // The window is the exception: describe uses the datepicker LABEL, which is the
  // checked preset's row text (not its value). No window → the new-events
  // ("added") label. The editor's When sheet is presets-only, so a single checked
  // d[] is the window.
  #temporal() {
    const checked = this.element.querySelector('.sheet[data-field="when"] input[name="d[]"]:checked')
    const label = checked?.closest(".opt")?.querySelector(".opt__label")?.textContent.trim()
    return label || this.addedLabelValue
  }
}
