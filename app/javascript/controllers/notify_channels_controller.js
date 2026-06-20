import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="notify-channels" on the editor's channels fieldset.
// In-app is the master channel: with it off the saved filter is a silent scope, so
// push + email can't ride on a digest that never fires — they're unchecked and
// disabled. Re-enabling in-app restores them, EXCEPT a channel locked for another
// reason (email with no address on file → data-locked), which stays disabled. The
// server enforces the same rule (SavedFilter#silence_other_channels).
export default class extends Controller {
  static targets = ["master", "dependent"]

  connect() {
    this.sync()
  }

  sync() {
    const on = this.masterTarget.checked
    this.dependentTargets.forEach((input) => {
      if (input.dataset.locked === "true") return
      input.disabled = !on
      if (!on) input.checked = false
    })
  }
}
