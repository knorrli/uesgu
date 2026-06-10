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
    // A Turbo cache restore can reconnect with the menu already open, but no
    // toggle event fires — start listening now so it stays dismissable.
    if (this.element.open) this.startListening()
  }

  // Bound to the <details> toggle event: start listening while open, stop when closed.
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
