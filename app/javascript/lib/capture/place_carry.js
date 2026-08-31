// Several acts on one poster share a venue; the date and time are what differ, so only
// this tuple carries between the candidates off one input.
const PLACE_FIELDS = ["place", "locality", "canton"]
const LOCALITY_MATCHES = 6

// Compare towns the way a contributor types them rather than the way they are spelt, so
// "zur" reaches "Zürich" and "neuch" reaches "Neuchâtel".
const fold = (value) => value.trim().toLowerCase().normalize("NFD").replace(/\p{Diacritic}/gu, "")

// The place tuple as it moves around one input's cards, and the town suggestions that
// fill it. `cards` is passed in at every entry point: which cards are on screen is the
// controller's to know, and this only needs the siblings of the one being acted on.
export class PlaceCarry {
  constructor(localities) {
    this.localities = localities
    this.shared = new Map()
  }

  // Fill the place tuple from a near-match instead of minting a variant spelling.
  applySuggestion(card, { name, locality, canton }, cards) {
    this.setField(card, "place", name, { normalized: true })
    if (locality) this.setField(card, "locality", locality, { normalized: true })
    if (canton) this.setField(card, "canton", canton, { normalized: true })
    this.pin(card, "place", locality && "locality", canton && "canton")
    this.share(card, cards)
  }

  // Fills the town and nothing else. The reason to tap one of these is that the venue is
  // NOT among the places being suggested, so writing a place here would replace the
  // contributor's reading of the poster with one nobody offered.
  applyLocality(card, { locality, canton }, cards) {
    this.setField(card, "locality", locality, { normalized: true })
    if (canton) this.setField(card, "canton", canton, { normalized: true })
    this.pin(card, "locality")
    this.share(card, cards)
    this.showMatches(card, [])
  }

  // The town list is drawn here rather than left to the browser: iOS Safari renders an
  // <input list> datalist in the keyboard's form-assistant bar, and hands that bar to its
  // own address autofill instead — so on the device most posters are captured on, the
  // towns never appear at all. Every locality the app knows is already in the page for
  // the canton, so matching costs no request.
  suggest(card, typed) {
    this.showMatches(card, this.matching(typed))
  }

  carry(card, name, value, cards) {
    // A field the contributor typed in themselves is their reading of the poster,
    // whatever a suggestion put there before.
    this.markNormalized(card, name, false)
    if (name === "locality") this.placeLocality(card, value)
    if (!PLACE_FIELDS.includes(name)) return

    this.pin(card, name)
    this.share(card, cards)
  }

  // Sticky here rather than a sweep of the cards on screen, so the tuple still reaches a
  // card that connects after the field was filled. An answer outranks a reading: once the
  // contributor has ruled on a field, a card landing later cannot put the model back in
  // charge of it.
  share(card, cards) {
    const row = card?.closest(".capture-row")
    if (!row) return

    const shared = this.shared.get(row.id) ?? { values: {}, answered: new Set() }
    PLACE_FIELDS.forEach((name) => {
      const value = this.fieldValue(card, name)
      if (!value || (shared.answered.has(name) && !this.pinned(card, name))) return

      shared.values[name] = value
      if (this.pinned(card, name)) shared.answered.add(name)
    })
    this.shared.set(row.id, shared)

    cards.filter((sibling) => sibling.closest(".capture-row") === row)
         .forEach((sibling) => this.fill(sibling, shared))
  }

  clear() {
    this.shared.clear()
  }

  // Completes what a card never printed, and carries a correction across the ones that
  // did: one poster is one venue in one town, so a value the model read wrong is wrong on
  // every card off it. Only an answer corrects — one model reading must not overwrite
  // another, which is what a bill across two halls comes down to.
  fill(card, shared) {
    if (card.dataset.state !== "open") return

    PLACE_FIELDS.forEach((name) => {
      const value = shared.values[name]
      if (!value || this.pinned(card, name)) return
      if (this.fieldValue(card, name) && !shared.answered.has(name)) return

      this.setField(card, name, value)
    })
  }

  // Matches take the row over while they stand: a ranked chip that also matches is in the
  // matches already, and one that does not is an answer to a question nobody is asking
  // any more.
  showMatches(card, matches) {
    const row = card?.querySelector("[data-suggestions=locality]")
    if (!row) return

    row.querySelectorAll("[data-typed]").forEach((chip) => chip.remove())
    row.querySelectorAll(".chip").forEach((chip) => { chip.hidden = matches.length > 0 })
    matches.forEach((name) => row.appendChild(this.chip(name)))
  }

  // Two letters before anything is offered, because one letter ranks nothing: the cap
  // would just take the first few of an alphabet.
  matching(typed) {
    const needle = fold(typed)
    if (needle.length < 2) return []

    const trailing = (name) => (fold(name).startsWith(needle) ? 0 : 1)
    return Object.keys(this.localities)
                 .filter((name) => fold(name).includes(needle))
                 .sort((a, b) => trailing(a) - trailing(b) || a.localeCompare(b))
                 .slice(0, LOCALITY_MATCHES)
  }

  chip(name) {
    const chip = document.createElement("button")
    chip.type = "button"
    chip.className = "chip"
    chip.textContent = name
    chip.dataset.typed = "true"
    chip.dataset.action = "capture#applyLocality"
    chip.dataset.captureLocalityParam = name
    chip.dataset.captureCantonParam = this.localities[name] ?? ""
    return chip
  }

  // Extraction computes the canton from the locality once, server-side, so a locality
  // changed here would otherwise keep the canton the one it replaced was placed in. A
  // locality matching nothing leaves the canton ALONE rather than clearing it — it may
  // hold the model's own postcode reading, which is why the field is still asked for at
  // all, or a value a human picked by hand.
  placeLocality(card, typed) {
    const canton = this.localities[typed.trim()]
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

  // The canton is computed from the locality and never asked for on its own, so an answer
  // for the town claims it too (see CapturesHelper#locality_chips).
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
}
