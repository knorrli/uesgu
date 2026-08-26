import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Several acts on one poster share a venue; the date and time are what differ, so
// only this tuple carries between the candidates off one input.
const PLACE_FIELDS = ["place", "locality", "canton"]
const LOCALITY_MATCHES = 6

// Compare towns the way a contributor types them rather than the way they are spelt,
// so "zur" reaches "Zürich" and "neuch" reaches "Neuchâtel".
const fold = (value) => value.trim().toLowerCase().normalize("NFD").replace(/\p{Diacritic}/gu, "")

// The extraction fan-out lives here rather than on the server: one request per input,
// because a batch cannot be held open in one and there is no queue to reach for (see
// EventCapture::Extractor). It also drives the review queue — one card on screen, the
// rest behind it in the strip.
//
// Connects to data-controller="capture".
export default class extends Controller {
  static targets = ["files", "text", "zone", "read", "input", "restart",
                    "rows", "strip", "card", "source", "stagingTitle", "reviewTitle",
                    "reviewHint", "genreOptions"]
  static values = {
    url: String,
    dropUrl: String,
    pending: String,
    error: String,
    undecodable: String,
    sourceAlt: String,
    maxEdge: { type: Number, default: 1568 },
    concurrency: { type: Number, default: 3 },
    localities: Object,
    blankUrl: String,
    byHand: String,
    foundOne: String,
    foundOther: String,
    done: Object,
    rereadLimit: { type: Number, default: 2 }
  }

  // What each row was read from, held only in the browser: nothing is uploaded for
  // storage, so this is the only copy a contributor can check a field against, and it
  // has to outlive the turbo-stream that replaces the whole row.
  initialize() {
    this.sources = new Map()
    this.places = new Map()
    this.inputs = new Map()
    this.rereads = new Map()
    this.currentId = null
  }

  disconnect() {
    this.reviewing(false)
    this.release(this.sources)
  }

  // Bounding the screen to the viewport is what gives the open card a height to divide
  // between its poster and its fields (see capture.css). On <html> because that is where
  // the rule that stops the scroll has to land — from <body> it only propagates, and the
  // propagated form still scrolls when something calls scrollIntoView.
  reviewing(on) {
    document.documentElement.classList.toggle("capture-reviewing", on)
  }

  release(held) {
    held.forEach(({ objectUrl }) => { if (objectUrl) URL.revokeObjectURL(objectUrl) })
    held.clear()
  }

  readFiles() {
    this.readImages(Array.from(this.filesTarget.files))
    // Cleared so that re-picking the same file still fires `change`.
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
    this.readImages(Array.from(event.dataTransfer.files).filter((file) => file.type.startsWith("image/")))
  }

  // Every row is stood up before the first read starts, so the strip states the whole
  // count from the moment the picker closes rather than growing as slots free up. A file
  // no browser can decode (a HEIC out of Finder, anything corrupt) fails its own row
  // here, while the filename is still what identifies it.
  //
  // The blob the request carries is the same one the card's source pane paints from:
  // nothing is re-derived, and nothing but that EXIF-stripped copy ever leaves the
  // device (see downscale).
  async readImages(files) {
    if (files.length === 0) return

    this.leavePicker()
    const reads = []
    for (const file of files) {
      const id = crypto.randomUUID()
      this.appendPending(id, file.name)
      const image = await this.downscale(file).catch(() => null)
      if (!image) {
        this.failRow(id, this.undecodableValue)
        continue
      }

      this.remember(this.rowId(id), id, { label: file.name, objectUrl: URL.createObjectURL(image), blob: image })
      reads.push(() => this.extract({ image, filename: file.name }, file.name, id))
    }
    this.run(reads)
  }

  // Picking files closes a dialog and dropping them ends a drag; typing ends in nothing,
  // so the one press on this screen belongs to the text field alone.
  readText() {
    const text = this.pendingText
    if (text === "") return

    const id = crypto.randomUUID()
    const label = text.slice(0, 40)
    this.textTarget.value = ""
    this.refreshRead()
    this.leavePicker()
    this.remember(this.rowId(id), id, { label, text })
    this.extract({ text }, label, id)
  }

  // Nothing to read, so nothing to send: the press is for the form.
  byHand() {
    this.leavePicker()
    this.addBlank(crypto.randomUUID(), this.byHandValue)
  }

  // Sending IS leaving the picker, there being nothing to assemble on it first. Someone
  // who wants more decides these and comes back — which is what finish() hands them.
  leavePicker() {
    this.inputTarget.hidden = true
    this.restartTarget.hidden = false
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
    this.places.clear()
    this.inputs.clear()
    this.rereads.clear()
    this.rowsTarget.replaceChildren()
    this.stripTarget.replaceChildren()
    this.stripTarget.hidden = true
    this.reviewing(false)
    this.currentId = null
    this.restartTarget.hidden = true
    this.inputTarget.hidden = false
    this.reviewTitleTarget.hidden = true
    this.reviewHintTarget.hidden = true
    this.stagingTitleTarget.hidden = false
    this.refreshRead()
  }

  refreshRead() {
    this.readTarget.disabled = this.pendingText === ""
  }

  get pendingText() {
    return this.textTarget.value.trim()
  }

  // The first card to land opens, so picking a single poster shows it rather than a
  // queue of one.
  cardTargetConnected(card) {
    this.stripTarget.hidden = false
    this.reviewing(true)
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
    // A queue of one is already open: there is nowhere to tap to.
    this.reviewHintTarget.hidden = count < 2
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
    this.cardTargets.forEach((card) => {
      const current = card.id === id
      card.hidden = !current
      this.stockGenres(card, current)
      if (current) this.rewind(card)
    })
    this.tiles.forEach((tile) => { tile.classList.toggle("is-current", tile.dataset.card === id) })
  }

  // Cards share one slot, so an arriving card inherits wherever the last one was left
  // — which after a decision is the bottom of a form, putting this card's title and the
  // shows it may duplicate above the top of the pane.
  rewind(card) {
    const body = card.querySelector(".review-card__body")
    if (body) body.scrollTop = 0
  }

  // The genre vocabulary lives once in the page and is lent to whichever card is open.
  // Only one card is ever on screen, so one copy is all the live DOM needs — and the
  // combobox reads its options off the listbox as it filters rather than caching them
  // when it connects, which is what makes lending them work at all.
  stockGenres(card, wanted) {
    const listbox = card.querySelector(".hw-combobox__listbox")
    if (!listbox || !this.hasGenreOptionsTarget) return
    if (!wanted) return listbox.replaceChildren()
    if (listbox.firstElementChild) return

    listbox.replaceChildren(this.genreOptionsTarget.content.cloneNode(true))
    this.markPickedGenres(card, listbox)
  }

  // A genre already on the card is spent: the combobox hides an option it holds in the
  // field, and a fresh clone knows nothing of what this card has picked.
  markPickedGenres(card, listbox) {
    const field = card.querySelector("[data-hw-combobox-target='hiddenField']")
    field?.value.split(",").map((name) => name.trim()).filter(Boolean).forEach((name) => {
      const option = listbox.querySelector(`[data-value="${CSS.escape(name)}"]`)
      if (!option) return

      option.setAttribute("data-multiselected", "")
      option.hidden = true
    })
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

    this.finish()
  }

  // A queue with nothing left to decide is a screen with nothing to do on it, so the
  // batch ends where it began. That throws the tiles away with it, and they are what
  // said which events went live — hence the count in the flash, the only receipt to
  // outlive the reset.
  finish() {
    const published = this.cardTargets.filter((card) => card.dataset.state === "published").length
    this.flash(this.doneMessage(published).replace("%{count}", published))
    this.startOver()
  }

  doneMessage(count) {
    if (count === 0) return this.doneValue.zero

    return count === 1 ? this.doneValue.one : this.doneValue.other
  }

  // Dropped once it has faded rather than left hidden in the region: this screen never
  // navigates, so nothing else would ever clear it and a second batch would announce
  // itself under the first one's ghost. The fade is .flash in application.css.
  flash(message) {
    const note = document.createElement("p")
    note.className = "flash notice"
    note.textContent = message
    note.addEventListener("animationend", () => note.remove())
    document.querySelector(".flashes")?.append(note)
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
    this.numberTiles()
  }

  // Renumbered on every arrival rather than assigned once: a poster yielding a second
  // event lands its tile inside its own group, which pushes every tile after it along.
  // Pending tiles are left out — one input can become two cards, so a number given
  // before the read lands is a number that moves.
  numberTiles() {
    this.tiles.forEach((tile, index) => { tile.dataset.index = index + 1 })
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
    this.showLocalityMatches(card, [])
  }

  // The town list is drawn here rather than left to the browser: iOS Safari renders an
  // <input list> datalist in the keyboard's form-assistant bar, and hands that bar to
  // its own address autofill instead — so on the device most posters are captured on,
  // the towns never appear at all. Every locality the app knows is already in the page
  // for the canton, so matching costs no request.
  suggestLocalities(event) {
    const card = event.target.closest(".capture-card")
    this.showLocalityMatches(card, this.matchingLocalities(event.target.value))
  }

  // Matches take the row over while they stand: a ranked chip that also matches is in
  // the matches already, and one that does not is an answer to a question nobody is
  // asking any more. The hint goes with them — it promises the towns will come up, and
  // they have.
  showLocalityMatches(card, matches) {
    const row = card?.querySelector("[data-suggestions=locality]")
    if (!row) return

    row.querySelectorAll("[data-typed]").forEach((chip) => chip.remove())
    row.querySelectorAll(".chip").forEach((chip) => { chip.hidden = matches.length > 0 })
    matches.forEach((name) => row.appendChild(this.localityChip(name)))
    const hint = card.querySelector("[data-locality-hint]")
    if (hint) hint.hidden = matches.length > 0
  }

  // Two letters before anything is offered, because one letter ranks nothing: the cap
  // would just take the first few of an alphabet.
  matchingLocalities(typed) {
    const needle = fold(typed)
    if (needle.length < 2) return []

    const trailing = (name) => (fold(name).startsWith(needle) ? 0 : 1)
    return Object.keys(this.localitiesValue)
                 .filter((name) => fold(name).includes(needle))
                 .sort((a, b) => trailing(a) - trailing(b) || a.localeCompare(b))
                 .slice(0, LOCALITY_MATCHES)
  }

  localityChip(name) {
    const chip = document.createElement("button")
    chip.type = "button"
    chip.className = "chip"
    chip.textContent = name
    chip.dataset.typed = "true"
    chip.dataset.action = "capture#applyLocality"
    chip.dataset.captureLocalityParam = name
    chip.dataset.captureCantonParam = this.localitiesValue[name] ?? ""
    return chip
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
