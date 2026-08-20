import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Several acts on one poster share a venue; the date and time are what differ, so
// only this tuple carries between the candidates off one input.
const PLACE_FIELDS = ["place", "locality", "canton"]

// The extraction fan-out lives here rather than on the server: one request per input,
// because a batch cannot be held open in one and there is no queue to reach for (see
// EventCapture::Extractor). It also drives the review queue — one card on screen, the
// rest behind it in the strip.
//
// Connects to data-controller="capture".
export default class extends Controller {
  static targets = ["files", "text", "zone", "items", "commit", "input", "restart",
                    "rows", "done", "strip", "card", "source"]
  static values = {
    url: String,
    pending: String,
    error: String,
    undecodable: String,
    remove: String,
    sourceAlt: String,
    maxEdge: { type: Number, default: 1568 },
    concurrency: { type: Number, default: 3 }
  }

  // What each row was read from, held only in the browser: nothing is uploaded for
  // storage, so this is the only copy a contributor can check a field against, and it
  // has to outlive the turbo-stream that replaces the whole row.
  initialize() {
    this.sources = new Map()
    this.staged = new Map()
    this.places = new Map()
    this.currentId = null
  }

  disconnect() {
    this.release(this.sources)
    this.release(this.staged)
  }

  release(held) {
    held.forEach(({ objectUrl }) => { if (objectUrl) URL.revokeObjectURL(objectUrl) })
    held.clear()
  }

  stageFiles() {
    this.stageAll(Array.from(this.filesTarget.files))
    // Cleared so that re-picking the same file after removing it still fires `change`.
    this.filesTarget.value = ""
  }

  dragOver(event) {
    event.preventDefault()
    this.zoneTarget.classList.add("is-over")
  }

  // dragleave also fires when the pointer crosses onto a CHILD of the zone, so the
  // highlight flickers unless the element being entered is checked.
  dragLeave(event) {
    if (!this.zoneTarget.contains(event.relatedTarget)) this.zoneTarget.classList.remove("is-over")
  }

  dropFiles(event) {
    event.preventDefault()
    this.zoneTarget.classList.remove("is-over")
    this.stageAll(Array.from(event.dataTransfer.files).filter((file) => file.type.startsWith("image/")))
  }

  async stageAll(files) {
    for (const file of files) await this.stageImage(file)
  }

  // Downscaled here rather than at send time because the shrunk blob is what the
  // thumbnail shows — and so a file no desktop browser can decode (a HEIC out of
  // Finder, anything corrupt) is caught while the batch can still be edited, instead
  // of landing as a dead row after it is sent.
  async stageImage(file) {
    const id = crypto.randomUUID()
    try {
      const image = await this.downscale(file)
      this.staged.set(id, { name: file.name, blob: image, objectUrl: URL.createObjectURL(image) })
    } catch {
      this.staged.set(id, { name: file.name, error: this.undecodableValue })
    }
    this.appendStaged(id)
  }

  stageText() {
    const text = this.textTarget.value.trim()
    if (text === "") return

    const id = crypto.randomUUID()
    this.staged.set(id, { name: text.slice(0, 40), text })
    this.textTarget.value = ""
    this.appendStaged(id)
  }

  appendStaged(id) {
    const staged = this.staged.get(id)
    const item = document.createElement("li")
    item.className = "drop-zone__item"
    item.dataset.staged = id
    if (staged.error) item.dataset.state = "undecodable"
    item.appendChild(staged.objectUrl ? this.poster(staged.objectUrl, staged.name) : this.snippet(staged))
    item.appendChild(this.removeButton(id, staged.name))
    this.itemsTarget.appendChild(item)
    this.refreshCommit()
  }

  unstage(event) {
    const id = event.params.staged
    const staged = this.staged.get(id)
    if (staged?.objectUrl) URL.revokeObjectURL(staged.objectUrl)
    this.staged.delete(id)
    this.itemsTarget.querySelector(`[data-staged="${id}"]`)?.remove()
    this.refreshCommit()
  }

  // The staged id becomes the row id, so the EXIF-stripped blob made at staging is
  // also what the card's source pane shows: nothing is re-derived and nothing but
  // that blob ever leaves the device.
  commit() {
    const batch = this.committable
    if (batch.length === 0) return

    this.inputTarget.hidden = true
    this.restartTarget.hidden = false
    batch.forEach((staged) => {
      this.sources.set(this.rowId(staged.id), staged.text ? { text: staged.text } : { objectUrl: staged.objectUrl })
    })
    this.run(batch.map((staged) => () =>
      this.extract(staged.text ? { text: staged.text } : { image: staged.blob, filename: staged.name },
                   staged.name, staged.id)))
  }

  // Destructive on purpose: there is no way back to a queue of half-decided cards, so
  // the honest offer is a clean second batch rather than a partial restore.
  startOver() {
    this.release(this.sources)
    this.release(this.staged)
    this.places.clear()
    this.itemsTarget.replaceChildren()
    this.rowsTarget.replaceChildren()
    this.stripTarget.replaceChildren()
    this.stripTarget.hidden = true
    this.currentId = null
    this.doneTarget.hidden = true
    this.restartTarget.hidden = true
    this.inputTarget.hidden = false
    this.refreshCommit()
  }

  refreshCommit() {
    this.commitTarget.disabled = this.committable.length === 0
  }

  get committable() {
    return Array.from(this.staged, ([id, staged]) => ({ id, ...staged })).filter((staged) => !staged.error)
  }

  // A staged image is its own label; anything without a picture needs words. A failed
  // file names itself, or a batch of five gives no clue which one to take back out.
  snippet(staged) {
    const box = document.createElement("span")
    box.className = "drop-zone__snippet"
    box.appendChild(this.line(staged.error ? staged.name : staged.text))
    if (staged.error) box.appendChild(this.line(staged.error, "drop-zone__reason"))
    return box
  }

  line(text, className) {
    const span = document.createElement("span")
    if (className) span.className = className
    span.textContent = text
    return span
  }

  removeButton(id, name) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "drop-zone__remove"
    button.dataset.action = "capture#unstage"
    button.dataset.captureStagedParam = id
    button.setAttribute("aria-label", `${this.removeValue}: ${name}`)
    const mark = document.createElement("span")
    mark.className = "ph ph-x"
    mark.setAttribute("aria-hidden", "true")
    button.appendChild(mark)
    return button
  }

  // The first card to land opens, so picking a single poster shows it rather than a
  // queue of one.
  cardTargetConnected(card) {
    this.stripTarget.hidden = false
    this.stripTarget.appendChild(this.tileFor(card))
    card.hidden = card.id !== this.currentId
    this.sharePlace(card)
    if (!this.currentId) this.open(card.id)
  }

  jump(event) {
    this.open(event.currentTarget.dataset.card)
  }

  open(id) {
    this.currentId = id
    this.cardTargets.forEach((card) => { card.hidden = card.id !== id })
    this.tiles.forEach((tile) => { tile.classList.toggle("is-current", tile.dataset.card === id) })
    this.doneTarget.hidden = true
  }

  // turbo:submit-end fires for a refusal too, and that response is the stream putting
  // the reason on a card the contributor is still looking at — so only a landed
  // publish decides one.
  decided(event) {
    if (!event.detail.success) return

    this.settle(event.target.closest(".capture-card"), "published")
  }

  reject(event) {
    this.settle(event.target.closest(".capture-card"), "dropped")
  }

  // Only publishing freezes a card: the event is live and the form behind it would
  // publish a second one. Rejecting is the reversible half, so a dropped card can be
  // reopened from its tile.
  settle(card, state) {
    card.dataset.state = state
    this.markTile(this.tileFor(card), state)
    if (state === "published") {
      card.querySelectorAll("input, select, button").forEach((field) => { field.disabled = true })
    }
    this.advance()
  }

  // Wraps, so a card left behind by a jump backwards is picked up rather than
  // stranded.
  advance() {
    const cards = this.cardTargets
    const from = cards.findIndex((card) => card.id === this.currentId)
    const next = cards.slice(from + 1).concat(cards.slice(0, from + 1))
                      .find((card) => card.dataset.state === "open")
    if (next) return this.open(next.id)

    cards.forEach((card) => { card.hidden = true })
    this.currentId = null
    this.doneTarget.hidden = false
  }

  // Full-bleed for the reason in review_card.css: the small print is what a poster is
  // being looked at for.
  zoom(event) {
    const pane = event.currentTarget
    if (pane.querySelector("img")) pane.classList.toggle("review-card__source--zoomed")
  }

  get tiles() {
    return Array.from(this.stripTarget.querySelectorAll("[data-card]"))
  }

  tileFor(card) {
    const existing = this.stripTarget.querySelector(`[data-card="${card.id}"]`)
    if (existing) return existing

    const tile = document.createElement("button")
    tile.type = "button"
    tile.className = "capture-queue__tile"
    tile.dataset.card = card.id
    tile.dataset.state = "open"
    tile.dataset.action = "capture#jump"
    tile.setAttribute("aria-label", card.querySelector(".capture-card__label")?.textContent.trim() ?? "")
    tile.appendChild(this.thumbnail(this.sources.get(card.closest(".capture-row")?.id)))
    return tile
  }

  markTile(tile, state) {
    tile.dataset.state = state
    tile.querySelector(".ph")?.remove()
    const mark = document.createElement("span")
    mark.className = state === "published" ? "ph ph-check-circle" : "ph ph-x"
    mark.setAttribute("aria-hidden", "true")
    tile.appendChild(mark)
  }

  // A pasted text has no picture to shrink, so its tile carries the head of the text
  // instead — the strip stays scannable when the queue mixes the two.
  thumbnail(source) {
    if (source?.objectUrl) return this.poster(source.objectUrl)

    const snippet = document.createElement("span")
    snippet.className = "capture-queue__snippet"
    snippet.textContent = source?.text?.slice(0, 24) ?? ""
    return snippet
  }

  // Fill the place tuple from a near-match instead of minting a variant spelling.
  applySuggestion(event) {
    const card = event.target.closest(".capture-card")
    const { name, locality, canton } = event.params
    this.setField(card, "place", name)
    if (locality) this.setField(card, "locality", locality)
    if (canton) this.setField(card, "canton", canton)
    this.sharePlace(card)
  }

  carryPlace(event) {
    if (PLACE_FIELDS.includes(event.target.name)) this.sharePlace(event.target.closest(".capture-card"))
  }

  // Sticky on the controller rather than a sweep of the cards on screen, so the tuple
  // still reaches a card that connects after the field was filled.
  sharePlace(card) {
    const row = card?.closest(".capture-row")
    if (!row) return

    const shared = this.places.get(row.id) ?? {}
    PLACE_FIELDS.forEach((name) => {
      const value = this.fieldValue(card, name)
      if (value) shared[name] = value
    })
    this.places.set(row.id, shared)

    this.cardTargets.filter((sibling) => sibling.closest(".capture-row") === row)
                    .forEach((sibling) => this.fillPlace(sibling, shared))
  }

  // Only ever completes, never corrects: card 3's venue can genuinely differ from the
  // two above it, and a decided card is not up for editing at all.
  fillPlace(card, shared) {
    if (card.dataset.state !== "open") return

    PLACE_FIELDS.forEach((name) => {
      if (shared[name] && !this.fieldValue(card, name)) this.setField(card, name, shared[name])
    })
  }

  fieldValue(card, name) {
    return card.querySelector(`[name="${name}"]`)?.value ?? ""
  }

  setField(card, name, value) {
    const field = card.querySelector(`[name="${name}"]`)
    if (field) field.value = value
  }

  // Capped rather than all-at-once: Puma runs three threads, so eight parallel
  // uploads would queue behind each other anyway while holding every byte of the
  // request in memory at the same time.
  async run(tasks) {
    const queue = tasks.slice()
    const workers = Array.from({ length: Math.min(this.concurrencyValue, queue.length) }, async () => {
      while (queue.length > 0) {
        // A task renders its own failure row, so a throw here must not take the
        // worker — and with it the rest of the queue — down with it.
        try { await queue.shift()() } catch { /* already surfaced on the row */ }
      }
    })
    await Promise.all(workers)
  }

  async extract(payload, label, id = crypto.randomUUID()) {
    if (!document.getElementById(this.rowId(id))) this.appendPending(id, label)

    const body = new FormData()
    body.append("row_id", id)
    body.append("label", label)
    if (payload.text !== undefined) body.append("text", payload.text)
    if (payload.image !== undefined) body.append("image", payload.image, payload.filename)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        body,
        headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": this.csrfToken }
      })
      // renderStreamMessage is a silent no-op on any body without a <turbo-stream>, so
      // an unchecked status leaves the row spinning forever on a 500, on a 403 after the
      // capability is revoked mid-session, and on an expired session (fetch follows the
      // redirect and hands back the login page).
      if (!response.ok) return this.failRow(id)

      const stream = await response.text()
      Turbo.renderStreamMessage(stream)
      // A provider failure comes back as a turbo-stream with status 200 — the request
      // succeeded, the extraction did not — so the response markup is the only honest
      // signal. It cannot be read off the page: Turbo performs the action on the NEXT
      // ANIMATION FRAME, so the pending row is still standing here, and reading that
      // scored every failure a success and cleared the textarea under a refused paste.
      return this.failureIn(stream) === null
    } catch {
      return this.failRow(id)
    }
  }

  // The template of a <turbo-stream> is inert markup, so the row has to be reached
  // through it rather than by querying the parsed document.
  failureIn(stream) {
    const template = new DOMParser().parseFromString(stream, "text/html").querySelector("turbo-stream template")
    return template?.content.querySelector("[data-failed]") ?? null
  }

  failRow(id, message = this.errorValue) {
    const row = document.getElementById(this.rowId(id))
    if (row) row.querySelector("[data-pending]").textContent = message
    return false
  }

  // Filled on connect rather than straight after renderStreamMessage: Turbo performs
  // the stream action on the next animation frame, so the row it paints does not
  // exist yet at the point the request settles.
  sourceTargetConnected(slot) {
    const source = this.sources.get(slot.closest(".capture-row")?.id)
    // Emptied first because a Turbo-cached snapshot restores an <img> whose object
    // URL this controller revoked on the way out — left alone it paints a broken
    // image, which is worse than the empty slot the restored card has earned.
    slot.replaceChildren()
    if (!source) return

    slot.appendChild(source.objectUrl ? this.poster(source.objectUrl) : this.excerpt(source.text))
  }

  poster(objectUrl, alt = this.sourceAltValue) {
    const image = document.createElement("img")
    image.src = objectUrl
    image.alt = alt
    return image
  }

  excerpt(text) {
    const paragraph = document.createElement("p")
    paragraph.className = "capture-row__excerpt"
    paragraph.textContent = text
    return paragraph
  }

  rowId(id) {
    return `capture-row-${id}`
  }

  appendPending(id, label) {
    const row = document.createElement("div")
    row.id = this.rowId(id)
    row.className = "capture-row"
    row.innerHTML = `<p class="field-label"></p><p class="muted" data-pending></p>`
    row.querySelector(".field-label").textContent = label
    row.querySelector("[data-pending]").textContent = this.pendingValue
    this.rowsTarget.appendChild(row)
  }

  // 1568px is where the provider's accuracy was measured. It happens on the client
  // because there is no image library in the bundle and none on the deployed box — and
  // the canvas re-encode drops EXIF, so a poster photo's GPS never leaves the device,
  // which a server-side resize could never achieve.
  //
  // Encoded BOTH ways because canvas PNG output is unoptimised: on a real poster
  // sample it came out at 1.81MB against 221KB as JPEG, 32% larger than the 1.37MB
  // source. Flat-colour screenshots, where PNG genuinely wins, still get PNG.
  async downscale(file) {
    const bitmap = await createImageBitmap(file)
    const scale = Math.min(1, this.maxEdgeValue / Math.max(bitmap.width, bitmap.height))
    const canvas = document.createElement("canvas")
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close()

    const encode = (type) => new Promise((resolve) => canvas.toBlob(resolve, type, 0.9))
    const [png, jpeg] = await Promise.all([encode("image/png"), encode("image/jpeg")])
    return png.size <= jpeg.size ? png : jpeg
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
