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
                    "rows", "done", "strip", "card", "source", "stagingTitle", "reviewTitle"]
  static values = {
    url: String,
    dropUrl: String,
    pending: String,
    error: String,
    undecodable: String,
    remove: String,
    sourceAlt: String,
    maxEdge: { type: Number, default: 1568 },
    concurrency: { type: Number, default: 3 },
    localities: Object,
    blankUrl: String,
    byHand: String,
    foundOne: String,
    foundOther: String,
    rereadLimit: { type: Number, default: 2 }
  }

  // What each row was read from, held only in the browser: nothing is uploaded for
  // storage, so this is the only copy a contributor can check a field against, and it
  // has to outlive the turbo-stream that replaces the whole row.
  initialize() {
    this.sources = new Map()
    this.staged = new Map()
    this.places = new Map()
    this.inputs = new Map()
    this.rereads = new Map()
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

  // A third input choice alongside images and pasted text. It stages like they do, so
  // a hand-entered event rides the same commit and lands in the same queue.
  stageBlank() {
    const id = crypto.randomUUID()
    this.staged.set(id, { name: this.byHandValue, blank: true })
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
    batch.filter((staged) => !staged.blank).forEach((staged) => {
      this.remember(this.rowId(staged.id), staged.id, staged.text
        ? { label: staged.name, text: staged.text }
        : { label: staged.name, objectUrl: staged.objectUrl, blob: staged.blob })
    })
    this.run(batch.map((staged) => () => staged.blank
      ? this.addBlank(staged.id, staged.name)
      : this.extract(staged.text ? { text: staged.text } : { image: staged.blob, filename: staged.name },
                     staged.name, staged.id)))
  }

  // The downscaled blob is held beside the object URL the pane paints from: a re-read
  // has to send the input a second time, and nothing was ever uploaded to fetch back.
  // `inputs` is what ties a row to it — a re-read's row is a different row off the
  // same input.
  remember(rowId, inputId, source) {
    this.sources.set(rowId, source)
    this.inputs.set(rowId, inputId)
  }

  // Destructive on purpose: there is no way back to a queue of half-decided cards, so
  // the honest offer is a clean second batch rather than a partial restore.
  startOver() {
    this.release(this.sources)
    this.release(this.staged)
    this.places.clear()
    this.inputs.clear()
    this.rereads.clear()
    this.itemsTarget.replaceChildren()
    this.rowsTarget.replaceChildren()
    this.stripTarget.replaceChildren()
    this.stripTarget.hidden = true
    this.currentId = null
    this.doneTarget.hidden = true
    this.restartTarget.hidden = true
    this.inputTarget.hidden = false
    this.reviewTitleTarget.hidden = true
    this.stagingTitleTarget.hidden = false
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
    box.appendChild(this.line(staged.text ?? staged.name))
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
    this.announceFound()
    this.placeCard(card)
    card.hidden = card.id !== this.currentId
    this.sharePlace(card)
    this.refreshRereads()
    if (!this.currentId) this.open(card.id)
  }

  // Held back until a card exists rather than swapped at commit time, so the heading
  // never states a count of zero while the reads are still in flight.
  announceFound() {
    const count = this.cardTargets.length
    const title = count === 1 ? this.foundOneValue : this.foundOtherValue
    this.reviewTitleTarget.textContent = title.replace("%{count}", count)
    this.stagingTitleTarget.hidden = true
    this.reviewTitleTarget.hidden = false
  }

  // A new row at the END of the queue, never a replacement: the read being disputed
  // stays on screen to compare against, and the strip's denominator grows.
  async reread(event) {
    const card = event.target.closest(".capture-card")
    const rowId = card.closest(".capture-row")?.id
    const input = this.inputs.get(rowId)
    const source = this.sources.get(rowId)
    const spent = this.rereads.get(input) ?? 0
    if (!source || spent >= this.rereadLimitValue) return

    this.rereads.set(input, spent + 1)
    const id = `${input}-r${spent + 1}`
    this.remember(this.rowId(id), input, source)
    this.refreshRereads()

    const sent = source.blob ? { image: source.blob, filename: source.label } : { text: source.text }
    await this.extract({ ...sent, ...this.reportFrom(card) }, source.label, id)
  }

  reportFrom(card) {
    const flags = Array.from(card.querySelectorAll(".capture-card__reread input:checked"))
    return {
      reread: true,
      wrong: flags.map((flag) => flag.value).join(","),
      note: card.querySelector(".capture-card__note")?.value ?? ""
    }
  }

  // Counted per INPUT and not per card: the cards a re-read produces would otherwise
  // arrive with a budget of their own, and every card off one poster spends the same
  // one. A published card is frozen and stays that way.
  refreshRereads() {
    this.cardTargets.forEach((card) => {
      const button = card.querySelector("[data-action~='capture#reread']")
      if (!button || card.dataset.state === "published") return

      const rowId = card.closest(".capture-row")?.id
      const left = this.rereadLimitValue - (this.rereads.get(this.inputs.get(rowId)) ?? 0)
      button.disabled = left <= 0 || !this.sources.has(rowId)
      const spent = card.querySelector("[data-spent]")
      if (spent) spent.hidden = left > 0
    })
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
    const card = event.target.closest(".capture-card")
    this.recordDrop(card)
    this.settle(card, "dropped")
  }

  // A drop is the only decision that never reaches the server, and it is the one the
  // field record most wants (see ExtractionFieldOutcome). Sent from the card's own
  // form, so it carries the proposals and the CSRF token, and deliberately not
  // awaited: the card is already gone, and a failed metric may not undo that.
  recordDrop(card) {
    const form = card?.querySelector("form")
    if (!form || !this.hasDropUrlValue) return

    fetch(this.dropUrlValue, { method: "POST", body: new FormData(form) }).catch(() => {})
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

  // One group per input. Several candidates off one poster then read as one thing
  // with parts, which is what lets the card header drop the "n of m" it used to need
  // to explain why two cards look alike.
  groupFor(rowId) {
    const existing = this.stripTarget.querySelector(`[data-row="${rowId}"]`)
    if (existing) return existing

    const group = document.createElement("div")
    group.className = "capture-queue__group"
    group.dataset.row = rowId
    this.stripTarget.appendChild(group)
    return group
  }

  placeCard(card) {
    const group = this.groupFor(card.closest(".capture-row")?.id)
    group.querySelector('[data-state="pending"]')?.remove()
    group.appendChild(this.tileFor(card))
  }

  // Stood up when the row is appended, not when a card lands, so the strip states the
  // denominator from the start — and so an input that yields nothing still gets a tile
  // saying so instead of vanishing from the queue entirely.
  pendingTile(rowId, label) {
    const tile = document.createElement("button")
    tile.type = "button"
    tile.className = "capture-queue__tile"
    tile.dataset.state = "pending"
    tile.disabled = true
    tile.setAttribute("aria-label", label)
    tile.appendChild(this.thumbnail(this.sources.get(rowId)))
    return tile
  }

  settleEmpty(id) {
    const pending = this.stripTarget.querySelector(`[data-row="${this.rowId(id)}"] [data-state="pending"]`)
    if (pending) this.markTile(pending, "failed")
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
    const title = card.querySelector('[name="title"]')?.value
    if (title) tile.setAttribute("aria-label", title)
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
    this.setField(card, "place", name, { normalized: true })
    if (locality) this.setField(card, "locality", locality, { normalized: true })
    if (canton) this.setField(card, "canton", canton, { normalized: true })
    this.pin(card, "place", locality && "locality", canton && "canton")
    this.sharePlace(card)
  }

  // Fills the town and nothing else. The reason to tap one of these is that the venue
  // is NOT among the places being suggested, so writing a place here would replace the
  // contributor's reading of the poster with one nobody offered.
  applyLocality(event) {
    const card = event.target.closest(".capture-card")
    const { locality, canton } = event.params
    this.setField(card, "locality", locality, { normalized: true })
    if (canton) this.setField(card, "canton", canton, { normalized: true })
    this.pin(card, "locality")
    this.sharePlace(card)
  }

  carryPlace(event) {
    const card = event.target.closest(".capture-card")
    // A field the contributor typed in themselves is their reading of the poster,
    // whatever a suggestion put there before.
    this.markNormalized(card, event.target.name, false)
    if (event.target.name === "locality") this.placeLocality(card, event.target.value)
    if (!PLACE_FIELDS.includes(event.target.name)) return

    this.pin(card, event.target.name)
    this.sharePlace(card)
  }

  // Extraction computes the canton from the locality once, server-side, so a locality
  // changed here would otherwise keep the canton the one it replaced was placed in.
  // A locality matching nothing leaves the canton ALONE rather than clearing it — it
  // may hold the model's own postcode reading, which is why the field is still asked
  // for at all, or a value a human picked by hand.
  placeLocality(card, typed) {
    const canton = this.localitiesValue[typed.trim()]
    if (!canton || canton === this.fieldValue(card, "canton")) return

    this.setField(card, "canton", canton, { normalized: true })
  }

  // Taking the registry's spelling is a normalisation, not a report that the model
  // misread the poster, and the two must not land in the same number (see
  // ExtractionFieldOutcome).
  markNormalized(card, name, normalized) {
    const flag = card?.querySelector(`[name="normalized_${name}"]`)
    if (flag) flag.value = normalized ? "1" : ""
  }

  // The canton is computed from the locality and never asked for on its own, so an
  // answer for the town claims it too (see CapturesHelper#locality_chips).
  pin(card, ...names) {
    const claimed = names.includes("locality") ? [...names, "canton"] : names
    claimed.filter(Boolean).forEach((name) => {
      const field = this.field(card, name)
      if (field) field.dataset.pinned = "true"
    })
  }

  pinned(card, name) {
    return this.field(card, name)?.dataset.pinned === "true"
  }

  // Sticky on the controller rather than a sweep of the cards on screen, so the tuple
  // still reaches a card that connects after the field was filled. An answer outranks
  // a reading: once the contributor has ruled on a field, a card landing later cannot
  // put the model back in charge of it.
  sharePlace(card) {
    const row = card?.closest(".capture-row")
    if (!row) return

    const shared = this.places.get(row.id) ?? { values: {}, answered: new Set() }
    PLACE_FIELDS.forEach((name) => {
      const value = this.fieldValue(card, name)
      if (!value || (shared.answered.has(name) && !this.pinned(card, name))) return

      shared.values[name] = value
      if (this.pinned(card, name)) shared.answered.add(name)
    })
    this.places.set(row.id, shared)

    this.cardTargets.filter((sibling) => sibling.closest(".capture-row") === row)
                    .forEach((sibling) => this.fillPlace(sibling, shared))
  }

  // Completes what a card never printed, and carries a correction across the ones that
  // did: one poster is one venue in one town, so a value the model read wrong is wrong
  // on every card off it. Only an answer corrects — one model reading must not
  // overwrite another, which is what a bill across two halls comes down to.
  fillPlace(card, shared) {
    if (card.dataset.state !== "open") return

    PLACE_FIELDS.forEach((name) => {
      const value = shared.values[name]
      if (!value || this.pinned(card, name)) return
      if (this.fieldValue(card, name) && !shared.answered.has(name)) return

      this.setField(card, name, value)
    })
  }

  field(card, name) {
    return card?.querySelector(`[name="${name}"]`)
  }

  fieldValue(card, name) {
    return this.field(card, name)?.value ?? ""
  }

  setField(card, name, value, { normalized = false } = {}) {
    const field = this.field(card, name)
    if (field) field.value = value
    if (normalized) this.markNormalized(card, name, true)
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
    if (payload.reread) {
      body.append("reread", "1")
      body.append("wrong", payload.wrong)
      body.append("note", payload.note)
    }

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
      // Counted off the stream rather than the page for the same reason the failure is:
      // Turbo performs the action on the next animation frame, so no card exists yet.
      if (this.cardsIn(stream) === 0) this.settleEmpty(id)
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

  // Asks the server for an empty card rather than building one here: the card is a
  // whole ERB form, and a second copy of it in JS would drift from the real one. The
  // pending row still has to exist first — a turbo-stream replace needs its target.
  async addBlank(id, label) {
    if (!document.getElementById(this.rowId(id))) this.appendPending(id, label)

    const body = new FormData()
    body.append("row_id", id)

    try {
      const response = await fetch(this.blankUrlValue, {
        method: "POST",
        body,
        headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": this.csrfToken }
      })
      if (!response.ok) return this.failRow(id)

      Turbo.renderStreamMessage(await response.text())
      return true
    } catch {
      return this.failRow(id)
    }
  }

  failureIn(stream) {
    return this.streamed(stream)?.querySelector("[data-failed]") ?? null
  }

  cardsIn(stream) {
    return this.streamed(stream)?.querySelectorAll(".capture-card").length ?? 0
  }

  // The template of a <turbo-stream> is inert markup, so what it carries has to be
  // reached through it rather than by querying the parsed document.
  streamed(stream) {
    const template = new DOMParser().parseFromString(stream, "text/html").querySelector("turbo-stream template")
    return template?.content ?? null
  }

  failRow(id, message = this.errorValue) {
    const row = document.getElementById(this.rowId(id))
    if (row) row.querySelector("[data-pending]").textContent = message
    this.settleEmpty(id)
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
    row.innerHTML = `<p class="capture-row__label field-label"></p><p class="muted" data-pending></p>`
    row.querySelector(".capture-row__label").textContent = label
    row.querySelector("[data-pending]").textContent = this.pendingValue
    this.rowsTarget.appendChild(row)

    this.stripTarget.hidden = false
    this.groupFor(this.rowId(id)).appendChild(this.pendingTile(this.rowId(id), label))
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
