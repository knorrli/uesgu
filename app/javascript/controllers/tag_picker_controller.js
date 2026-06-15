import { Controller } from "@hotwired/stimulus"

// A no-navigation multiselect tag input for forms. A hotwire-combobox picks from
// existing options; each pick becomes a removable chip carrying its own hidden
// field, submitted with the surrounding form. When the combobox has name_when_new
// set, free text is allowed and routed to a separate param — so the rule "what"
// field collects styles (param-value) AND free-text queries (query-param-value)
// in one input, exactly like the landing-page filter, with the two kept apart.
//
// Connects to data-controller="tag-picker".
export default class extends Controller {
  static targets = ["chips"]
  static values = { param: String, queryParam: String }

  // hw-combobox:selection fires for both an existing pick and a committed
  // free-text value; detail.fieldName tells them apart (it equals the combobox's
  // name_when_new value for free text).
  add(event) {
    const { value, fieldName } = event.detail
    if (!value) return

    const isNew = fieldName && fieldName === event.target.dataset.hwComboboxNameWhenNewValue
    const param = (isNew && this.hasQueryParamValue) ? this.queryParamValue : this.paramValue

    if (!this.#has(param, value)) {
      this.chipsTarget.appendChild(this.#chip(param, value))
      this.#announce()
    }
    this.#clearInput()
  }

  remove(event) {
    event.currentTarget.closest("[data-tag-chip]")?.remove()
    this.#announce()
  }

  // Let an outer controller (rule-name preview) react to chip changes.
  #announce() {
    this.dispatch("change", { bubbles: true })
  }

  #has(param, value) {
    return [...this.chipsTarget.querySelectorAll(`input[name="${param}"]`)]
      .some((input) => input.value === value)
  }

  // Built with text nodes (never innerHTML) so a free-text value can't inject markup.
  #chip(param, value) {
    const chip = document.createElement("span")
    chip.className = "tag active"
    chip.dataset.tagChip = ""

    const input = document.createElement("input")
    input.type = "hidden"
    input.name = param
    input.value = value

    const label = document.createElement("span")
    label.textContent = value

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "tag__remove ph ph-x"
    remove.setAttribute("aria-label", value)
    remove.dataset.action = "tag-picker#remove"

    chip.append(input, label, remove)
    return chip
  }

  // Reset the picker for the next selection: blank the visible input and fire an
  // input event so the gem clears its query (the dropdown shows all options again).
  #clearInput() {
    const input = this.element.querySelector("input[role='combobox']")
    if (!input) return
    input.value = ""
    input.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
