import { Controller } from "@hotwired/stimulus"

// Live false-positive check for the discard-rule editor: as the admin types the
// pattern (or changes the venue scope), point the preview turbo frame at the
// preview endpoint with the current values (debounced). Setting frame.src lets
// Turbo fetch + render the matching events without submitting the form. Unlike
// autosave_controller, this DOES react to typing (input) — previewing before
// saving is the whole point.
//
// Connects to data-controller="preview". Inputs carry data-preview-target="field"
// + data-preview-param="<query key>"; the frame carries data-preview-target="frame".
export default class extends Controller {
  static targets = ["frame", "field"]
  static values = { url: String, delay: { type: Number, default: 250 } }

  connect() {
    this.refresh = this.refresh.bind(this)
    this.refresh()
  }

  schedule() {
    clearTimeout(this.timer)
    this.timer = setTimeout(this.refresh, this.delayValue)
  }

  refresh() {
    const params = new URLSearchParams()
    this.fieldTargets.forEach((field) => params.set(field.dataset.previewParam, field.value))
    this.frameTarget.src = `${this.urlValue}?${params}`
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
