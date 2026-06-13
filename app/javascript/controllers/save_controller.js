import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="save" on a per-event "save this show" toggle.
// Self-contained (one per button, no cross-element sync): optimistically flip
// the bookmark, persist in the background, revert on failure.
export default class extends Controller {
  static values = { eventId: Number, saved: Boolean }

  toggle() {
    const saved = !this.savedValue
    this.#apply(saved)
    this.#persist(saved).catch(() => this.#apply(!saved))
  }

  #apply(saved) {
    this.savedValue = saved
    this.element.classList.toggle("saved", saved)
    this.element.setAttribute("aria-pressed", saved)
  }

  async #persist(saved) {
    const response = await fetch("/saved_events/toggle", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify({ event_id: this.eventIdValue })
    })

    if (!response.ok) throw new Error(`save toggle failed: ${response.status}`)
  }
}
