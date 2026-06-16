import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="clipboard". Copies the source field's value and
// briefly swaps the button label to confirm. Falls back to selecting the field
// when the async clipboard API is unavailable (insecure context / old browser).
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

  // Tapping the field selects the whole URL, so manual copy is one gesture.
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
