import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["title"]
  static values = { scopeAll: String, addedLabel: String }

  connect() {
    this.update()
  }

  update() {
    const what = [...this.#values("g"), ...this.#values("q")]
    const where = this.#values("l")

    const parts = [what.length ? what.join(", ") : this.scopeAllValue]
    if (where.length) parts.push(where.join(", "))
    parts.push(this.#temporal())

    this.titleTarget.textContent = parts.join(" · ")
  }

  #values(name) {
    return [...this.element.querySelectorAll(`input[name="${name}[]"]:checked`)].map((i) => i.value)
  }

  #temporal() {
    const checked = this.element.querySelector('.sheet[data-field="when"] input[name="d[]"]:checked')
    const label = checked?.closest(".opt")?.querySelector(".opt__label")?.textContent.trim()
    return label || this.addedLabelValue
  }
}
