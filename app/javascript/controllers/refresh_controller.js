import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { interval: { type: Number, default: 5000 } }

  connect() {
    this.timer = setInterval(() => this.reload(), this.intervalValue)
  }

  reload() {
    if (document.hidden) return // don't poll a backgrounded tab

    if (window.Turbo) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    } else {
      window.location.reload()
    }
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
