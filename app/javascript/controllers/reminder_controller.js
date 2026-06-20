import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="reminder" on the saved-shows day-of reminder
// toggle. Like save_controller: optimistically keep the checkbox where the user
// put it, persist in the background, revert on failure. The checkbox IS the
// state, so there's no separate value to track.
export default class extends Controller {
  static targets = ["checkbox"]

  toggle() {
    const enabled = this.checkboxTarget.checked
    this.#persist(enabled).catch(() => { this.checkboxTarget.checked = !enabled })
  }

  async #persist(enabled) {
    const response = await fetch("/saved_events/reminders", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify({ enabled })
    })

    if (!response.ok) throw new Error(`reminder toggle failed: ${response.status}`)
  }
}
