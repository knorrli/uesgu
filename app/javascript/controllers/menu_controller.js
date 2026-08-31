import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onDocClick = (event) => {
      if (!this.element.contains(event.target)) this.element.open = false
    }
    this.onKeydown = (event) => {
      if (event.key === "Escape") this.element.open = false
    }
    if (this.element.open) this.startListening()
  }

  toggle() {
    if (this.element.open) {
      this.startListening()
    } else {
      this.stopListening()
    }
  }

  startListening() {
    document.addEventListener("click", this.onDocClick)
    document.addEventListener("keydown", this.onKeydown)
  }

  stopListening() {
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    this.stopListening()
  }
}
