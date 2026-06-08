import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="menu" on a <details> element.
// Closes the menu when clicking outside it or pressing Escape.
export default class extends Controller {
  connect() {
    this.onDocClick = (event) => {
      if (!this.element.contains(event.target)) this.element.open = false
    }
    this.onKeydown = (event) => {
      if (event.key === "Escape") this.element.open = false
    }
  }

  // Bound to the <details> toggle event: start listening while open, stop when closed.
  toggle() {
    if (this.element.open) {
      document.addEventListener("click", this.onDocClick)
      document.addEventListener("keydown", this.onKeydown)
    } else {
      this.stopListening()
    }
  }

  stopListening() {
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    this.stopListening()
  }
}
