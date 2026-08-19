import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The extraction fan-out lives here rather than on the server: one request per
// input, because a batch cannot be held open in one and there is no queue to reach
// for (see EventCapture::Extractor).
//
// Connects to data-controller="capture".
export default class extends Controller {
  static targets = ["files", "text", "rows", "empty", "actions", "accept", "source"]
  static values = {
    url: String,
    pending: String,
    error: String,
    undecodable: String,
    sourceAlt: String,
    maxEdge: { type: Number, default: 1568 },
    concurrency: { type: Number, default: 3 }
  }

  // What each row was read from, held only in the browser. Nothing is uploaded for
  // storage, so this store is the only copy a contributor can check a field
  // against, and it has to outlive the turbo-stream that replaces the whole row.
  initialize() {
    this.sources = new Map()
  }

  disconnect() {
    this.sources.forEach(({ objectUrl }) => { if (objectUrl) URL.revokeObjectURL(objectUrl) })
    this.sources.clear()
  }

  pickFiles() {
    const files = Array.from(this.filesTarget.files)
    if (files.length === 0) return

    this.filesTarget.value = ""
    this.run(files.map((file) => () => this.extractImage(file)))
  }

  // The textarea is cleared only once the extraction has landed. A file can be
  // re-picked from disk; a long paste from a newsletter cannot be, and the provider
  // fails often enough that clearing first loses it for real.
  pickText() {
    const text = this.textTarget.value.trim()
    if (text === "") return

    const id = crypto.randomUUID()
    this.sources.set(this.rowId(id), { text })
    this.run([() => this.extract({ text }, text.slice(0, 40), id)
      .then((landed) => {
        if (landed && this.textTarget.value.trim() === text) this.textTarget.value = ""
      })])
  }

  // Unchecking "keep" does not lift `required`, so one dropped row missing the
  // canton no poster prints makes the whole form unsubmittable, pointing at a row
  // the contributor does not want. The marker outlives the removal so re-checking
  // restores it.
  //
  // Publish is revealed from here rather than once the last extraction settles: a
  // stream lands a frame later than the request that fetched it (see #extract), so
  // that check ran before the row existed and left Publish hidden on a batch that
  // had extracted fine. A row carrying no candidate never reaches here, so a failed
  // batch still cannot offer a button that submits nothing.
  acceptTargetConnected(checkbox) {
    const fieldset = checkbox.closest(".capture-candidate")
    fieldset.querySelectorAll("[required]").forEach((field) => field.setAttribute("data-required-when-kept", ""))
    this.applyRequired(checkbox)
    this.actionsTarget.hidden = false
  }

  syncRequired(event) {
    this.applyRequired(event.target)
  }

  applyRequired(checkbox) {
    const fieldset = checkbox.closest(".capture-candidate")
    fieldset.querySelectorAll("[data-required-when-kept]").forEach((field) => {
      field.required = checkbox.checked
    })
  }

  // Fill the place tuple from a near-match instead of minting a variant spelling.
  // Scoped to the fieldset the chip sits in — every candidate carries its own.
  applySuggestion(event) {
    const fieldset = event.target.closest(".capture-candidate")
    const { name, locality, canton } = event.params
    this.setField(fieldset, "place", name)
    if (locality) this.setField(fieldset, "locality", locality)
    if (canton) this.setField(fieldset, "canton", canton)
  }

  setField(fieldset, suffix, value) {
    const field = fieldset.querySelector(`[name$="[${suffix}]"]`)
    if (field) field.value = value
  }

  // Capped rather than all-at-once: Puma runs three threads, so eight parallel
  // uploads would queue behind each other anyway while holding every byte of the
  // request in memory at the same time.
  async run(tasks) {
    this.emptyTarget.hidden = true

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

  // The row is appended BEFORE the decode, not after: createImageBitmap rejects on
  // a HEIC picked from Finder (accept="image/*" allows it and no desktop browser
  // decodes it) and on anything corrupt, and with the row created afterwards that
  // threw before anything was on screen — the picker cleared, the Publish button
  // appeared, and nothing else happened.
  async extractImage(file) {
    const id = crypto.randomUUID()
    this.appendPending(id, file.name)

    let image
    try {
      image = await this.downscale(file)
    } catch {
      // Not a network problem — say the thing the contributor can act on, which is
      // the same advice Adapters::Image gives for a file it cannot read.
      return this.failRow(id, this.undecodableValue)
    }

    // The downscaled blob, never the picked File: the canvas re-encode has already
    // dropped EXIF, so the preview inherits "the GPS never leaves the device".
    this.sources.set(this.rowId(id), { objectUrl: URL.createObjectURL(image) })
    return this.extract({ image, filename: file.name }, file.name, id)
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
      // renderStreamMessage is a silent no-op on any body without a <turbo-stream>,
      // so an unchecked status leaves the row spinning forever on a 500, on a 403
      // after the capability is revoked mid-session, and on an expired session
      // (fetch follows the redirect and hands back the login page) — indistinguishable
      // from a slow provider, which is the exact failure this rescue exists to prevent.
      if (!response.ok) return this.failRow(id)

      const stream = await response.text()
      Turbo.renderStreamMessage(stream)
      // A provider failure comes back as a turbo-stream with status 200 — the
      // request succeeded, the extraction did not — so the row is the only honest
      // signal of whether anything was read. It has to be read out of the markup:
      // Turbo performs the action on the NEXT ANIMATION FRAME, so the page still
      // holds the pending row here and every failure read as a success, which
      // cleared the textarea out from under a paste the provider had just refused.
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

  // Returns false so a caller can tell a landed extraction from a failed one.
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
    // image, which is worse than the empty slot the restored row has earned.
    slot.replaceChildren()
    if (!source) return

    slot.appendChild(source.objectUrl ? this.poster(source.objectUrl) : this.excerpt(source.text))
  }

  poster(objectUrl) {
    const image = document.createElement("img")
    image.src = objectUrl
    image.alt = this.sourceAltValue
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

  // The long edge is capped at 1568px, which is where the provider's accuracy was
  // measured. It happens here because there is no image library in the bundle and
  // none on the deployed box, so the server cannot resize. Re-encoding through the
  // canvas also drops EXIF, so a poster photo's GPS never leaves the device — which
  // the server could never have achieved, the metadata having already travelled.
  //
  // Encoded BOTH ways and the smaller one wins, rather than picking by source
  // type. Measured on a real poster sample already at 1568px: canvas PNG came out at
  // 1.81MB — 32% LARGER than the 1.37MB source, because canvas PNG output is
  // unoptimised — against 221KB as JPEG. Keeping PNG for PNG sources would have
  // sent eight times the necessary bytes on exactly the input this feature is for.
  // Flat-colour screenshots, where PNG genuinely wins, still get PNG; the rule
  // decides per image instead of guessing from the file extension.
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
