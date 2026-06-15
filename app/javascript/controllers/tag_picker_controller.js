import { Controller } from "@hotwired/stimulus"
import { searchForSuggestion } from "lib/search_for"

// Make the combobox feel like a <select>: don't re-filter the option list when
// the listbox closes or a selection is forced in. Global prototype patches —
// they take effect for every combobox as soon as this module loads (all
// controllers are eager-loaded), which is what both filters want.
import HwComboboxController from "controllers/hw_combobox_controller"
HwComboboxController.prototype._lockInSelection = function () {}
HwComboboxController.prototype._forceSelectionAndFilter = function (option) {
  this._forceSelectionWithoutFiltering(option)
}

// Param → Phosphor glyph for a chip's leading icon. Mirrors TagsHelper#
// filter_chip_icon so a chip built here matches one rendered server-side.
const CHIP_GLYPH = {
  "s[]": "ph-music-notes",
  "q[]": "ph-magnifying-glass",
  "l[]": "ph-map-pin",
  "d[]": "ph-calendar-dots",
}

// A no-navigation multiselect collector shared by the events filter and the
// notification-rule form, so the two stay visually and behaviourally in step. A
// hotwire-combobox (or, for "when", the datepicker) feeds picks in; each becomes
// a removable chip carrying its own hidden field, submitted with the form. Each
// input field names its destination param(s) via action params:
//   data-tag-picker-field-param="s[]"        (the pick param)
//   data-tag-picker-query-field-param="q[]"  (free text, when allowed)
//
// With auto-submit (the events filter) every add/remove re-submits so the list
// filters live and the chips come back server-rendered; without it (the rule
// form) chips accumulate client-side until the user saves.
//
// Connects to data-controller="tag-picker".
export default class extends Controller {
  static targets = ["chips", "searchFor", "whatField"]
  static values = { autoSubmit: Boolean }

  connect() {
    this.#setupSearchFor()
  }

  disconnect() {
    if (this.styleInput && this.onStyleInput) {
      this.styleInput.removeEventListener("input", this.onStyleInput)
    }
  }

  // hw-combobox:selection fires for both an existing pick and a committed
  // free-text value; detail.fieldName equals the combobox's name_when_new value
  // for free text, which routes it to queryField instead of field.
  add(event) {
    const { value, fieldName } = event.detail
    if (!value) return

    const { field, queryField } = event.params
    const isNew = fieldName && fieldName === event.target.dataset.hwComboboxNameWhenNewValue
    const param = isNew && queryField ? queryField : field

    this.#addChip(param, value)
    this.#clearField(event.currentTarget)
  }

  // datepicker:selection — value is a preset key or a raw range string;
  // detail.label is the human label. On the auto-submit filter the chip is
  // re-rendered server-side with a localized label immediately, so the label
  // passed here only matters for the brief pre-navigation flash.
  addRange(event) {
    const { value, label } = event.detail
    if (value) this.#addChip(event.params.field, value, label)
  }

  remove(event) {
    event.currentTarget.closest("[data-tag-chip]")?.remove()
    this.#announce()
    this.#submit()
  }

  // Commit the "Search for «X»" row as a free-text query — the pointer
  // counterpart to typing the text and pressing enter (the gem's name_when_new
  // flow already covers the keyboard path).
  addSearchQuery() {
    const value = this.searchForTarget.dataset.value
    if (value) this.#addChip("q[]", value)
  }

  #addChip(param, value, label) {
    if (this.#has(param, value)) return
    this.chipsTarget.appendChild(this.#chip(param, value, label ?? value))
    this.#announce()
    this.#submit()
  }

  // Auto-submit re-runs the filter (and re-renders the chips server-side). The
  // tag-picker is mounted on the form on the events page; the rule form leaves
  // auto-submit off, so this is a no-op there.
  #submit() {
    if (this.autoSubmitValue) this.element.closest("form")?.requestSubmit()
  }

  // Let an outer controller (the rule editor's autosave) react to chip changes.
  #announce() {
    this.dispatch("change", { bubbles: true })
  }

  #has(param, value) {
    return [...this.chipsTarget.querySelectorAll(`input[name="${param}"]`)]
      .some((input) => input.value === value)
  }

  // Built with text nodes (never innerHTML) so a free-text value can't inject
  // markup. Mirrors tags/_filter_chip.html.erb.
  #chip(param, value, label) {
    const chip = document.createElement("span")
    chip.className = "tag active"
    chip.dataset.tagChip = ""

    const input = document.createElement("input")
    input.type = "hidden"
    input.name = param
    input.value = value

    const icon = document.createElement("span")
    icon.className = `ph ${CHIP_GLYPH[param] || "ph-lightning"}`
    icon.setAttribute("aria-hidden", "true")

    const text = document.createElement("span")
    text.textContent = label

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "tag__remove ph ph-x"
    remove.setAttribute("aria-label", value)
    remove.dataset.action = "tag-picker#remove"

    chip.append(input, icon, text, remove)
    return chip
  }

  // Reset the field that fired for the next selection: blank its visible input
  // and fire an input event so the gem clears its query (all options show again).
  #clearField(wrapper) {
    const input = wrapper.querySelector("input[role='combobox']")
    if (!input) return
    input.value = ""
    input.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // The "What" combobox accepts free text (name_when_new) but the gem gives no
  // hint. Mirror the mobile sheet: drop a "Search for «X»" row into the dropdown
  // and reveal it (shared search_for logic) when the typed text matches no
  // option. Optional — only wired when a searchFor target is present.
  #setupSearchFor() {
    if (!this.hasSearchForTarget) return

    const scope = this.hasWhatFieldTarget ? this.whatFieldTarget : this.element
    this.styleListbox = scope.querySelector('[role="listbox"]')
    this.styleInput = scope.querySelector('input[role="combobox"]')
    if (!this.styleListbox || !this.styleInput) return

    // Move the row to the top of the dropdown so it rides the listbox's
    // open/close and scroll and sits above the options, like the mobile sheet.
    this.styleListbox.prepend(this.searchForTarget)

    this.onStyleInput = () => this.#refreshSearchFor()
    this.styleInput.addEventListener("input", this.onStyleInput)
  }

  #refreshSearchFor() {
    const labels = [...this.styleListbox.querySelectorAll('[role="option"][data-value]')]
      .map((option) => option.dataset.value)
    const suggestion = searchForSuggestion(
      this.styleInput.value,
      labels,
      this.searchForTarget.dataset.searchForTemplate
    )

    if (suggestion.show) {
      this.searchForTarget.querySelector("[data-search-for-label]").textContent = suggestion.label
      this.searchForTarget.dataset.value = suggestion.value
      this.searchForTarget.hidden = false
    } else {
      this.searchForTarget.hidden = true
    }
  }
}
