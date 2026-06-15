import { Controller } from "@hotwired/stimulus"

// Autosave a form on any change — the rule editor has no Save button. Every edit
// (a filter chip added/removed, a schedule select, a channel checkbox) persists
// immediately and the server re-renders the form inside its turbo frame with the
// canonical state: chips sorted + deduped, dropdowns excluding what's already
// picked, the window shown as a tag, the derived name refreshed.
//
// One debounced submit coalesces a combobox's native `change` with the
// tag-picker:change it triggers, and smooths a burst of edits into a single
// round-trip. Typing fires `input`, not `change`, so it never submits mid-type.
//
// Connects to data-controller="autosave" on the <form>.
export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  connect() {
    this.onChange = () => {
      clearTimeout(this.timer)
      this.timer = setTimeout(() => this.element.requestSubmit(), this.delayValue)
    }
    this.element.addEventListener("change", this.onChange)
    this.element.addEventListener("tag-picker:change", this.onChange)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.element.removeEventListener("change", this.onChange)
    this.element.removeEventListener("tag-picker:change", this.onChange)
  }
}
