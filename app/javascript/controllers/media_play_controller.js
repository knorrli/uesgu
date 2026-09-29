import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon"]
  static values = { eventId: Number, title: String, provider: String, src: String, eventUrl: String }

  connect() {
    this.#show(document.getElementById("media-dock")?.dataset.eventId === String(this.eventIdValue))
  }

  toggle() {
    this.dispatch("toggle", {
      target: window,
      prefix: "media",
      detail: {
        eventId: this.eventIdValue,
        title: this.titleValue,
        eventUrl: this.eventUrlValue,
        provider: this.providerValue,
        src: this.srcValue
      }
    })
  }

  sync({ detail: { eventId } }) {
    this.#show(eventId === this.eventIdValue)
  }

  #show(playing) {
    this.element.classList.toggle("playing", playing)
    this.element.setAttribute("aria-pressed", playing)
    this.iconTarget.classList.toggle("ph-play", !playing)
    this.iconTarget.classList.toggle("ph-stop", playing)
  }
}
