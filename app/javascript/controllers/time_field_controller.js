import { Controller } from "@hotwired/stimulus"

// Clears a native time input, which nothing else can: an event whose start time is
// unknown is a real state (the listing, the digest and the .ics all render it), and
// the control itself offers no way back to an empty value. See shared/_time_field.
export default class extends Controller {
  static targets = ["input", "clear"]

  connect() {
    this.refresh()
  }

  refresh() {
    this.clearTarget.hidden = this.inputTarget.value === ""
  }

  clear(event) {
    // The field sits inside its <label>: a click that reaches the label's activation
    // behaviour lands on the input and re-opens the picker just cleared.
    event.preventDefault()
    this.inputTarget.value = ""
    this.refresh()
  }
}
