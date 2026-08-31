import { Controller } from "@hotwired/stimulus"

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
