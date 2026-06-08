import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="calendar"
// Expands a day's events inline as a full-width row beneath the clicked week,
// relocating the persistent #day-detail Turbo Frame into that row. Clicking the
// already-open day collapses it again (without reloading the frame).
export default class extends Controller {
  select(event) {
    const link = event.currentTarget

    // Toggle: a second click on the open day collapses it. Prevent the default
    // so Turbo doesn't pointlessly reload the frame we're about to hide.
    if (link.classList.contains("selected")) {
      event.preventDefault()
      this.collapse()
      return
    }

    this.deselectAll()
    link.classList.add("selected")
    this.expandAfter(link)
  }

  collapse() {
    this.deselectAll()
    const row = this.detailRow()
    if (row) row.hidden = true
  }

  // Move the #day-detail frame into a full-width row directly after the week
  // (tr) containing the clicked day, so the loaded events render inline.
  expandAfter(link) {
    const frame = this.frame()
    const week = link.closest("tr")
    if (!frame || !week) return

    const row = this.detailRow(true)
    row.hidden = false
    row.firstElementChild.appendChild(frame)
    week.after(row)

    frame.addEventListener(
      "turbo:frame-load",
      () => frame.scrollIntoView({ behavior: "smooth", block: "nearest" }),
      { once: true }
    )
  }

  deselectAll() {
    this.element
      .querySelectorAll(".calendar-day-link.selected")
      .forEach((el) => el.classList.remove("selected"))
  }

  frame() {
    return document.getElementById("day-detail")
  }

  // The inline row hosting the detail frame; lazily created on first expand.
  detailRow(create = false) {
    let row = this.element.querySelector("tr.day-detail-row")
    if (!row && create) {
      row = document.createElement("tr")
      row.className = "day-detail-row"
      const cell = document.createElement("td")
      cell.colSpan = 7
      row.appendChild(cell)
    }
    return row
  }
}
