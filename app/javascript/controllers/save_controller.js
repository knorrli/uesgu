import { Controller } from "@hotwired/stimulus"

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
    this.dispatch("toggled", { detail: { saved }, bubbles: true })
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
