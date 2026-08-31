import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button"]
  static values = { copied: String }

  async copy() {
    const text = this.sourceTarget.value
    try {
      await navigator.clipboard.writeText(text)
      this.#flash()
    } catch {
      this.sourceTarget.focus()
      this.sourceTarget.select()
    }
  }

  select() {
    this.sourceTarget.select()
  }

  #flash() {
    if (!this.hasButtonTarget || !this.hasCopiedValue) return
    const original = this.buttonTarget.textContent
    this.buttonTarget.textContent = this.copiedValue
    setTimeout(() => { this.buttonTarget.textContent = original }, 1500)
  }
}
