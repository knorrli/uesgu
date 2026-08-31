import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["master", "dependent"]

  connect() {
    this.sync()
  }

  sync() {
    const on = this.masterTarget.checked
    this.dependentTargets.forEach((input) => {
      if (input.dataset.locked === "true") return
      input.disabled = !on
      if (!on) input.checked = false
    })
  }
}
