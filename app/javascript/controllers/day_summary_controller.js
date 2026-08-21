import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="day-summary" on a list date block. Keeps that
// header's saved (♥) count in step with the save toggles inside the day, which
// bubble up as save:toggled.
export default class extends Controller {
  static targets = ["saved"]

  adjustSaved(event) {
    if (!this.hasSavedTarget) return

    const badge = this.savedTarget
    const next = Math.max(0, (parseInt(badge.textContent, 10) || 0) + (event.detail.saved ? 1 : -1))
    badge.textContent = next
    badge.hidden = next === 0
  }
}
