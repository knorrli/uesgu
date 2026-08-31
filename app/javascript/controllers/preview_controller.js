import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame", "field"]
  static values = { url: String, delay: { type: Number, default: 250 } }

  connect() {
    this.refresh = this.refresh.bind(this)
    this.refresh()
  }

  schedule() {
    clearTimeout(this.timer)
    this.timer = setTimeout(this.refresh, this.delayValue)
  }

  refresh() {
    const params = new URLSearchParams()
    this.fieldTargets.forEach((field) => params.set(field.dataset.previewParam, field.value))
    this.frameTarget.src = `${this.urlValue}?${params}`
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
