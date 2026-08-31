import { posterImage } from "lib/capture/sources"

// `failed` carries its own mark rather than the ×: nothing came back is not a decision
// anybody made, and sharing the drop's glyph filed it as one.
const MARKS = { published: "ph-check-circle", dropped: "ph-x", failed: "ph-warning-circle" }

const SNIPPET = 24

const rowIdOf = (card) => card.closest(".capture-row")?.id

// One tile per candidate, grouped by the input it came off.
export class CaptureQueueStrip {
  constructor(element, sources, posterAlt) {
    this.element = element
    this.sources = sources
    this.posterAlt = posterAlt
  }

  get tiles() {
    return Array.from(this.element.querySelectorAll("[data-card]"))
  }

  // Stood up when the row is appended rather than when a card lands, so the strip states
  // the denominator from the start — and so an input that yields nothing still gets a
  // tile saying so instead of vanishing from the queue entirely.
  appendPending(rowId, label) {
    this.element.hidden = false
    const tile = document.createElement("button")
    tile.type = "button"
    tile.className = "capture-queue__tile"
    tile.dataset.state = "pending"
    tile.disabled = true
    tile.setAttribute("aria-label", label)
    tile.appendChild(this.thumbnail(rowId))
    this.groupFor(rowId).appendChild(tile)
  }

  // The tile is stood up before the downscale that gives it a picture to show, so the
  // thumbnail lands when there is one rather than by holding the whole strip back for it.
  dress(rowId) {
    this.pendingIn(rowId)?.replaceChildren(this.thumbnail(rowId))
  }

  place(card) {
    const rowId = rowIdOf(card)
    this.element.hidden = false
    this.pendingIn(rowId)?.remove()
    this.groupFor(rowId).appendChild(this.tileFor(card))
    this.number()
  }

  mark(card, state) {
    this.markTile(this.tileFor(card), state)
  }

  markFailed(rowId) {
    const pending = this.pendingIn(rowId)
    if (pending) this.markTile(pending, "failed")
  }

  highlight(cardId) {
    this.tiles.forEach((tile) => { tile.classList.toggle("is-current", tile.dataset.card === cardId) })
  }

  clear() {
    this.element.replaceChildren()
    this.element.hidden = true
  }

  // One group per input. Several candidates off one poster then read as one thing with
  // parts, which is what lets the card header drop the "n of m" it would otherwise need
  // to explain why two cards look alike.
  groupFor(rowId) {
    const existing = this.element.querySelector(`[data-row="${rowId}"]`)
    if (existing) return existing

    const group = document.createElement("div")
    group.className = "capture-queue__group"
    group.dataset.row = rowId
    this.element.appendChild(group)
    return group
  }

  pendingIn(rowId) {
    return this.element.querySelector(`[data-row="${rowId}"] [data-state="pending"]`)
  }

  tileFor(card) {
    const existing = this.element.querySelector(`[data-card="${card.id}"]`)
    if (existing) return existing

    const tile = document.createElement("button")
    tile.type = "button"
    tile.className = "capture-queue__tile"
    tile.dataset.card = card.id
    tile.dataset.state = "open"
    tile.dataset.action = "capture#jump"
    const title = card.querySelector('[name="title"]')?.value
    if (title) tile.setAttribute("aria-label", title)
    tile.appendChild(this.thumbnail(rowIdOf(card)))
    return tile
  }

  markTile(tile, state) {
    tile.dataset.state = state
    tile.querySelector(".ph")?.remove()
    const mark = document.createElement("span")
    mark.className = `ph ${MARKS[state]}`
    mark.setAttribute("aria-hidden", "true")
    tile.appendChild(mark)
  }

  // Renumbered on every arrival rather than assigned once: a poster yielding a second
  // event lands its tile inside its own group, which pushes every tile after it along.
  // Pending tiles are left out — one input can become two cards, so a number given
  // before the read lands is a number that moves.
  number() {
    this.tiles.forEach((tile, index) => { tile.dataset.index = index + 1 })
  }

  // A pasted text has no picture to shrink, so its tile carries the head of the text
  // instead — the strip stays scannable when the queue mixes the two.
  thumbnail(rowId) {
    const source = this.sources.get(rowId)
    if (source?.objectUrl) return posterImage(source.objectUrl, this.posterAlt)

    const snippet = document.createElement("span")
    snippet.className = "capture-queue__snippet"
    snippet.textContent = source?.text?.slice(0, SNIPPET) ?? ""
    return snippet
  }
}
