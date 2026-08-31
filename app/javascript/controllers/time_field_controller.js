import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "clear"]

  connect() {
    this.refresh()
  }

  refresh() {
    this.clearTarget.hidden = this.inputTarget.value === ""
  }

  clear(event) {
    event.preventDefault()
    this.inputTarget.value = ""
    this.refresh()
  }
}
