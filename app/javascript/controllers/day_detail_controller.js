import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="day-detail"
//
// The open day is rendered server-side inline in the calendar grid (URL state).
// Frame navigation keeps the page scroll put, so an opened day below the fold
// would stay off-screen — nudge it into view, but only as far as needed.
export default class extends Controller {
  connect() {
    this.element.scrollIntoView({ behavior: "smooth", block: "nearest" })
  }
}
