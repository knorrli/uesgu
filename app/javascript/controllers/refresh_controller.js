import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="refresh". Reloads the page on an interval so a
// long-running view (an in-progress scraper sweep) shows new per-scraper
// results as they land — no websockets needed. The marker element is rendered
// only while there's something to watch, so once the run finishes the reloaded
// page omits it and the polling stops on its own.
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
