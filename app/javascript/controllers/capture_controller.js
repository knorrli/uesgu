import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { downscale, isImage, isImageType } from "lib/downscale"
import { runPool } from "lib/task_pool"
import { streamedContent } from "lib/turbo_stream"
import { CaptureSources, posterImage } from "lib/capture/sources"
import { CaptureQueueStrip } from "lib/capture/queue_strip"
import { PlaceCarry } from "lib/capture/place_carry"

// The extraction fan-out lives here rather than on the server: one request per input,
// because a batch cannot be held open in one and there is no queue to reach for (see
// EventCapture::Extractor). It also drives the review queue — one card on screen, the
// rest behind it in the strip.
//
// Connects to data-controller="capture".
export default class extends Controller {
  static targets = ["files", "text", "zone", "read", "paste", "pasteError", "input",
                    "restart", "byHand", "rows", "strip", "card", "source", "stagingTitle",
                    "reviewTitle", "reviewHint", "genreOptions"]
  static values = {
    url: String,
    dropUrl: String,
    pending: String,
    error: String,
    undecodable: String,
    sourceAlt: String,
    pasted: String,
    // 1568px is where the provider's accuracy was measured.
    maxEdge: { type: Number, default: 1568 },
    // Puma runs three threads, so eight parallel uploads would queue behind each other
    // anyway while holding every byte of the request in memory at the same time.
    concurrency: { type: Number, default: 3 },
    localities: Object,
    foundOne: String,
    foundOther: String,
    done: Object,
    rereadLimit: { type: Number, default: 2 }
  }

  initialize() {
    this.sources = new CaptureSources()
    this.places = new PlaceCarry(this.localitiesValue)
    this.strip = new CaptureQueueStrip(this.stripTarget, this.sources, this.sourceAltValue)
    this.currentId = null
  }

  // Rendered first and taken away here rather than the reverse: the styleguide renders
  // the partial with no controller in reach, so a button that shipped hidden would
  // leave the specimen demonstrating nothing.
  connect() {
    if (!navigator.clipboard?.read) this.pasteTarget.hidden = true
  }

  disconnect() {
    this.sources.clear()
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
    this.readImages(Array.from(event.dataTransfer.files).filter(isImage))
  }

  // The way in that costs no download: copy a poster wherever it is and paste it here,
  // rather than saving it to the photo library first. A phone has no keystroke for
  // that, so it is a button — Safari answers the read with a system paste prompt of
  // its own, and a declined prompt rejects and is not a failure to report.
  //
  // `read()` is started before anything is awaited: the tap's transient activation is
  // what buys that prompt, and the first await spends it.
  async pasteImages() {
    this.pasteErrorTarget.hidden = true

    let items
    try {
      items = await navigator.clipboard.read()
    } catch {
      return
    }

    const images = await this.clipboardImages(items)
    if (images.length === 0) {
      this.pasteErrorTarget.hidden = false
      return
    }

    this.readImages(images)
  }

  // Ctrl/Cmd+V anywhere on the picker, which is the desktop door — there is no such
  // gesture on a phone, where the button is the only one. A field that can hold what
  // was copied keeps its own paste: an image rides along with the text on a clipboard
  // filled from a rich document, and there the text is what was meant.
  pasted(event) {
    if (this.inputTarget.hidden) return
    if (event.target.closest("input, textarea, [contenteditable]") && event.clipboardData.getData("text")) return

    const images = Array.from(event.clipboardData.files).filter(isImage)
    if (images.length === 0) return

    event.preventDefault()
    this.readImages(images)
  }

  // Named after the gesture: a clipboard image has no filename, and the tile's
  // thumbnail is what tells two pasted posters apart.
  async clipboardImages(items) {
    const images = []
    for (const item of items) {
      const type = item.types.find(isImageType)
      if (type) images.push(new File([await item.getType(type)], this.pastedValue, { type }))
    }
    return images
  }

  // Every row is stood up before the first read starts, so the strip states the whole
  // count from the moment the picker closes rather than growing as slots free up. A file
  // no browser can decode (a HEIC out of Finder, anything corrupt) fails its own row
  // here, while the filename is still what identifies it.
  //
  // The blob the request carries is the same one the card's source pane paints from:
  // nothing is re-derived, and nothing but that EXIF-stripped copy ever leaves the
  // device (see lib/downscale.js).
  async readImages(files) {
    if (files.length === 0) return

    this.leavePicker()
    const reads = []
    for (const file of files) {
      const id = crypto.randomUUID()
      this.appendPending(id, file.name)
      const image = await downscale(file, this.maxEdgeValue).catch(() => null)
      if (!image) {
        this.failRow(id, this.undecodableValue)
        continue
      }

      this.sources.remember(this.rowId(id), id,
                            { label: file.name, objectUrl: URL.createObjectURL(image), blob: image })
      this.strip.dress(this.rowId(id))
      reads.push(() => this.extract({ image, filename: file.name }, file.name, id))
    }
    runPool(reads, this.concurrencyValue)
  }

  // Picking files closes a dialog and dropping them ends a drag; typing ends in nothing,
  // which is the whole reason this one has a button of its own.
  readText() {
    const text = this.pendingText
    if (text === "") return

    const id = crypto.randomUUID()
    const label = text.slice(0, 40)
    this.textTarget.value = ""
    this.refreshRead()
    this.leavePicker()
    this.sources.remember(this.rowId(id), id, { label, text })
    this.extract({ text }, label, id)
  }

  // Sending IS leaving the picker, there being nothing to assemble on it first. Someone
  // who wants more decides these and comes back — which is what finish() hands them.
  leavePicker() {
    this.pasteErrorTarget.hidden = true
    this.inputTarget.hidden = true
    this.restartTarget.hidden = false
    this.byHandTarget.hidden = true
  }

  // Destructive on purpose: there is no way back to a queue of half-decided cards, so
  // the honest offer is a clean second batch rather than a partial restore.
  startOver() {
    this.sources.clear()
    this.places.clear()
    this.strip.clear()
    this.rowsTarget.replaceChildren()
    this.currentId = null
    this.restartTarget.hidden = true
    this.byHandTarget.hidden = false
    this.inputTarget.hidden = false
    this.reviewTitleTarget.hidden = true
    this.reviewHintTarget.hidden = true
    this.stagingTitleTarget.hidden = false
    window.scrollTo({ top: 0 })
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
    this.announceFound()
    this.strip.place(card)
    card.hidden = card.id !== this.currentId
    this.places.share(card, this.cardTargets)
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
    const source = this.sources.get(rowId)
    if (!source || this.sources.spent(rowId) >= this.rereadLimitValue) return

    const input = this.sources.inputFor(rowId)
    const id = `${input}-r${this.sources.spend(rowId)}`
    this.sources.remember(this.rowId(id), input, source)
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

  refreshRereads() {
    this.cardTargets.forEach((card) => {
      const button = card.querySelector("[data-action~='capture#reread']")
      if (!button || card.dataset.state === "published") return

      const rowId = card.closest(".capture-row")?.id
      const left = this.rereadLimitValue - this.sources.spent(rowId)
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
    })
    this.strip.highlight(id)
    // After the loop, not inside it: hiding the cards below shortens the document, and a
    // scroll set against the taller one is clamped back to somewhere short of the card.
    this.reveal(this.cardTargets.find((card) => card.id === id))
  }

  // Cards share one slot on a page that scrolls as a whole, so a card opening after a
  // decision inherits the scroll position the last one was left at — the bottom of a
  // form, with this card's title and the shows it may duplicate above the top of the
  // screen. Clearance for the sticky strip comes from the card's own scroll-margin.
  reveal(card) {
    card?.scrollIntoView()
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
    this.strip.mark(card, state)
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

  applySuggestion(event) {
    this.places.applySuggestion(event.target.closest(".capture-card"), event.params, this.cardTargets)
  }

  applyLocality(event) {
    this.places.applyLocality(event.target.closest(".capture-card"), event.params, this.cardTargets)
  }

  suggestLocalities(event) {
    this.places.suggest(event.target.closest(".capture-card"), event.target.value)
  }

  carryPlace(event) {
    this.places.carry(event.target.closest(".capture-card"), event.target.name, event.target.value,
                      this.cardTargets)
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
      // A provider failure comes back as a turbo-stream with status 200 — the request
      // succeeded, the extraction did not — so the response markup is the only honest
      // signal, for both the failure and the count. It cannot be read off the page:
      // Turbo performs the action on the NEXT ANIMATION FRAME, so the pending row is
      // still standing here, and reading that scored every failure a success and
      // cleared the textarea under a refused paste.
      const content = streamedContent(stream)
      if (this.cardsIn(content) === 0) this.settleEmpty(id)
      return this.failureIn(content) === null
    } catch {
      return this.failRow(id)
    }
  }

  failureIn(content) {
    return content?.querySelector("[data-failed]") ?? null
  }

  cardsIn(content) {
    return content?.querySelectorAll(".capture-card").length ?? 0
  }

  settleEmpty(id) {
    this.strip.markFailed(this.rowId(id))
  }

  // Named, unlike the row it replaces: while a read is in flight the filename is one
  // more thing to read and nothing to act on, but a row that failed is the only place
  // its input is still identified. Same two parts as a failure the server rendered
  // (see captures/_extraction).
  failRow(id, message = this.errorValue) {
    const row = document.getElementById(this.rowId(id))
    if (row) row.replaceChildren(this.rowLabel(row.dataset.label), this.rowFailure(message))
    this.settleEmpty(id)
    return false
  }

  rowLabel(label) {
    const line = document.createElement("p")
    line.className = "capture-row__label field-label"
    line.textContent = label
    return line
  }

  rowFailure(message) {
    const line = document.createElement("p")
    line.className = "capture-row__failure"
    line.textContent = message
    return line
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

    slot.appendChild(source.objectUrl ? posterImage(source.objectUrl, this.sourceAltValue)
                                      : this.excerpt(source.text))
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

  // Says one thing: a contributor picked these files seconds ago and there is nothing
  // to do about the one in flight, so the filename is carried by the tile's label and
  // by whatever replaces this row, not by a second quiet line here.
  appendPending(id, label) {
    const row = document.createElement("div")
    row.id = this.rowId(id)
    row.className = "capture-row"
    row.dataset.label = label
    const pending = document.createElement("p")
    pending.dataset.pending = ""
    pending.textContent = this.pendingValue
    row.appendChild(pending)
    this.rowsTarget.appendChild(row)

    this.strip.appendPending(this.rowId(id), label)
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
