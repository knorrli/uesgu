import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="calendar"
// Highlights the clicked day and scrolls the loaded day-detail frame into view.
export default class extends Controller {
  select(event) {
    const link = event.currentTarget

    this.element
      .querySelectorAll(".calendar-day-link.selected")
      .forEach((el) => el.classList.remove("selected"))
    link.classList.add("selected")

    const frame = document.getElementById("day-detail")
    if (!frame) return
    frame.addEventListener(
      "turbo:frame-load",
      () => frame.scrollIntoView({ behavior: "smooth", block: "nearest" }),
      { once: true }
    )
  }
}
