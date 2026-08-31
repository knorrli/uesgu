import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { downscale, isImage, isImageType } from "lib/downscale"
import { runPool } from "lib/task_pool"
import { streamedContent } from "lib/turbo_stream"
import { CaptureSources, posterImage } from "lib/capture/sources"
import { CaptureQueueStrip } from "lib/capture/queue_strip"
import { PlaceCarry } from "lib/capture/place_carry"
import { PlaceFields } from "lib/capture/place_fields"

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
    maxEdge: { type: Number, default: 1568 },
    concurrency: { type: Number, default: 3 },
    localities: Object,
    places: Object,
    foundOne: String,
    foundOther: String,
    done: Object,
    rereadLimit: { type: Number, default: 2 }
  }

  initialize() {
    this.sources = new CaptureSources()
    this.fields = new PlaceFields({ places: this.placesValue, localities: this.localitiesValue },
                                  this.identifier)
    this.carry = new PlaceCarry()
    this.strip = new CaptureQueueStrip(this.stripTarget, this.sources, this.sourceAltValue)
    this.currentId = null
  }

  connect() {
    if (!navigator.clipboard?.read) this.pasteTarget.hidden = true
  }

  disconnect() {
    this.sources.clear()
  }

  readFiles() {
    this.readImages(Array.from(this.filesTarget.files))
    this.filesTarget.value = ""
  }

  dragOver(event) {
    event.preventDefault()
    this.zoneTarget.classList.add("is-over")
  }

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

  pasted(event) {
    if (this.inputTarget.hidden) return
    if (event.target.closest("input, textarea, [contenteditable]") && event.clipboardData.getData("text")) return

    const images = Array.from(event.clipboardData.files).filter(isImage)
    if (images.length === 0) return

    event.preventDefault()
    this.readImages(images)
  }

  async clipboardImages(items) {
    const images = []
    for (const item of items) {
      const type = item.types.find(isImageType)
      if (type) images.push(new File([await item.getType(type)], this.pastedValue, { type }))
    }
    return images
  }

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

  leavePicker() {
    this.pasteErrorTarget.hidden = true
    this.inputTarget.hidden = true
    this.restartTarget.hidden = false
    this.byHandTarget.hidden = true
  }

  startOver() {
    this.sources.clear()
    this.carry.clear()
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

  cardTargetConnected(card) {
    this.announceFound()
    this.strip.place(card)
    card.hidden = card.id !== this.currentId
    this.carry.share(card, this.cardTargets)
    this.refreshRereads()
    if (!this.currentId) this.open(card.id)
  }

  announceFound() {
    const count = this.cardTargets.length
    const title = count === 1 ? this.foundOneValue : this.foundOtherValue
    this.reviewTitleTarget.textContent = title.replace("%{count}", count)
    this.stagingTitleTarget.hidden = true
    this.reviewTitleTarget.hidden = false
    this.reviewHintTarget.hidden = count < 2
  }

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
    this.reveal(this.cardTargets.find((card) => card.id === id))
  }

  reveal(card) {
    card?.scrollIntoView()
  }

  stockGenres(card, wanted) {
    const listbox = card.querySelector(".hw-combobox__listbox")
    if (!listbox || !this.hasGenreOptionsTarget) return
    if (!wanted) return listbox.replaceChildren()
    if (listbox.firstElementChild) return

    listbox.replaceChildren(this.genreOptionsTarget.content.cloneNode(true))
    this.markPickedGenres(card, listbox)
  }

  markPickedGenres(card, listbox) {
    const field = card.querySelector("[data-hw-combobox-target='hiddenField']")
    field?.value.split(",").map((name) => name.trim()).filter(Boolean).forEach((name) => {
      const option = listbox.querySelector(`[data-value="${CSS.escape(name)}"]`)
      if (!option) return

      option.setAttribute("data-multiselected", "")
      option.hidden = true
    })
  }

  decided(event) {
    if (!event.detail.success) return

    this.settle(event.target.closest(".capture-card"), "published")
  }

  reject(event) {
    const card = event.target.closest(".capture-card")
    this.recordDrop(card)
    this.settle(card, "dropped")
  }

  recordDrop(card) {
    const form = card?.querySelector("form")
    if (!form || !this.hasDropUrlValue) return

    fetch(this.dropUrlValue, { method: "POST", body: new FormData(form) }).catch(() => {})
  }

  settle(card, state) {
    card.dataset.state = state
    this.strip.mark(card, state)
    if (state === "published") {
      card.querySelectorAll("input, select, button").forEach((field) => { field.disabled = true })
    }
    this.advance()
  }

  advance() {
    const cards = this.cardTargets
    const from = cards.findIndex((card) => card.id === this.currentId)
    const next = cards.slice(from + 1).concat(cards.slice(0, from + 1))
                      .find((card) => card.dataset.state === "open")
    if (next) return this.open(next.id)

    this.finish()
  }

  finish() {
    const published = this.cardTargets.filter((card) => card.dataset.state === "published").length
    this.flash(this.doneMessage(published).replace("%{count}", published))
    this.startOver()
  }

  doneMessage(count) {
    if (count === 0) return this.doneValue.zero

    return count === 1 ? this.doneValue.one : this.doneValue.other
  }

  flash(message) {
    const note = document.createElement("p")
    note.className = "flash notice"
    note.textContent = message
    note.addEventListener("animationend", () => note.remove())
    document.querySelector(".flashes")?.append(note)
  }

  zoom(event) {
    const pane = event.currentTarget
    if (pane.querySelector("img")) pane.classList.toggle("review-card__source--zoomed")
  }

  applySuggestion(event) {
    const card = this.cardFor(event)
    this.fields.applySuggestion(card, event.params)
    this.carry.share(card, this.cardTargets)
  }

  applyLocality(event) {
    const card = this.cardFor(event)
    this.fields.applyLocality(card, event.params)
    this.carry.share(card, this.cardTargets)
  }

  suggestPlaces(event) {
    this.fields.suggest(this.cardFor(event), "place", event.target.value)
  }

  suggestLocalities(event) {
    this.fields.suggest(this.cardFor(event), "locality", event.target.value)
  }

  typedPlace(event) {
    const card = this.cardFor(event)
    this.fields.typed(card, event.target.name, event.target.value)
    this.carry.share(card, this.cardTargets)
  }

  cardFor(event) {
    return event.target.closest(".capture-card")
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
