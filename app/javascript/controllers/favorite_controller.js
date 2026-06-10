import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="favorite"
//
// Inline follow/unfollow for location and style tags. A tag can appear many
// times in the list (a style across events, a venue across days), so a click
// optimistically flips every matching heart at once, then persists in the
// background. It also recomputes the calendar/list day markers in place from
// the followed set, so every favorite indicator updates the instant a tag is
// toggled — no reload, no server round-trip. The server stays authoritative on
// any full render; this just keeps the toggle feeling immediate.
export default class extends Controller {
  static values = { followed: Array }
  static targets = ["favoritesFilter"]

  connect() {
    // The user's follows as namespaced keys ("l:<location>" / "s:<style>"),
    // matched against each day's keys to decide its marker.
    this.followed = new Set(this.followedValue)
  }

  toggle(event) {
    const { type, value } = event.params
    const button = event.currentTarget
    const wasFollowed = button.classList.contains("followed")

    this.#apply(type, value, !wasFollowed)

    this.#persist(type, value).catch(() => this.#apply(type, value, wasFollowed))
  }

  // Reflect a follow state everywhere it shows: the matching hearts, the
  // in-memory followed set, and the calendar/list day markers.
  #apply(type, value, followed) {
    this.#matching(type, value).forEach((el) => {
      el.classList.toggle("followed", followed)
      el.setAttribute("aria-pressed", followed)
    })

    const key = `${type === "location" ? "l" : "s"}:${value}`
    followed ? this.followed.add(key) : this.followed.delete(key)

    this.#refreshMarkers()
    this.#refreshFavoritesFilter()
  }

  // The "apply my favorites" shortcut is rendered hidden until the user follows
  // something. Reveal/hide it from the live follow set, and keep its href
  // pointing at the current favorites (unless the filter is already applied, in
  // which case the link clears back to the full programme).
  #refreshFavoritesFilter() {
    if (!this.hasFavoritesFilterTarget) return

    const link = this.favoritesFilterTarget
    link.hidden = this.followed.size === 0

    if (this.followed.size > 0 && !link.classList.contains("active")) {
      const params = new URLSearchParams()
      this.followed.forEach((followKey) => {
        const separator = followKey.indexOf(":")
        const param = followKey.slice(0, separator) === "l" ? "l[]" : "s[]"
        params.append(param, followKey.slice(separator + 1))
      })
      link.href = `/?${params}`
    }
  }

  #matching(type, value) {
    return this.element.querySelectorAll(
      `[data-favorite-type-param="${CSS.escape(type)}"][data-favorite-value-param="${CSS.escape(value)}"]`
    )
  }

  // A day marker — a calendar cell's corner heart or a list date header's heart
  // — shows when any tag on that day is followed. Each marker carries its day's
  // keys, so this is a cheap set check that touches only the markers.
  #refreshMarkers() {
    this.element.querySelectorAll("[data-day-keys]").forEach((marker) => {
      const keys = JSON.parse(marker.dataset.dayKeys)
      marker.hidden = !keys.some((key) => this.followed.has(key))
    })
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
