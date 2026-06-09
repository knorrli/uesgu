import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="favorite"
//
// Inline follow/unfollow for location and style tags. A tag can appear many
// times in the list (a style across events, a venue across days), so a click
// optimistically flips every matching heart at once, then persists in the
// background. The server owns everything else: day markers, the favorites
// filter, and the canonical heart state are re-rendered authoritatively on the
// next render (opening a day, month nav, filter, reload) — so this controller
// only has to make the click itself feel instant.
export default class extends Controller {
  toggle(event) {
    const { type, value } = event.params
    const button = event.currentTarget
    const wasFollowed = button.classList.contains("followed")

    this.#flip(type, value, !wasFollowed)

    this.#persist(type, value).catch(() => this.#flip(type, value, wasFollowed))
  }

  // Flip every heart for this tag — it can repeat across the list.
  #flip(type, value, followed) {
    this.#matching(type, value).forEach((el) => {
      el.classList.toggle("followed", followed)
      el.setAttribute("aria-pressed", followed)
    })
  }

  #matching(type, value) {
    return this.element.querySelectorAll(
      `[data-favorite-type-param="${CSS.escape(type)}"][data-favorite-value-param="${CSS.escape(value)}"]`
    )
  }

  async #persist(type, value) {
    const response = await fetch("/favorites/toggle", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify({ type, value })
    })

    if (!response.ok) throw new Error(`favorite toggle failed: ${response.status}`)
  }
}
