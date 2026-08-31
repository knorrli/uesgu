const MATCHES = 6

// Compare names the way a contributor types them rather than the way they are spelt, so
// "zur" reaches "Zürich" and "dachstok" reaches "Dachstock".
export const fold = (value) => value.trim().toLowerCase().normalize("NFD").replace(/\p{Diacritic}/gu, "")

export const field = (card, name) => card?.querySelector(`[name="${name}"]`)

export const fieldValue = (card, name) => field(card, name)?.value ?? ""

export const pinned = (card, name) => field(card, name)?.dataset.pinned === "true"

export const setField = (card, name, value) => {
  const target = field(card, name)
  if (target) target.value = value
}

const APPLY = { place: "applySuggestion", locality: "applyLocality" }

// The venue, town and canton of one event, and the vocabulary offered beside them.
// Everything the app already carries is in the page, so matching what is typed costs
// no request — which is also why there is no second, disagreeing ranking: the chips a
// model's read put in the row and the ones typing puts there come off one list.
//
// The rows are drawn here rather than left to the browser: iOS Safari renders an
// <input list> datalist in the keyboard's form-assistant bar, and hands that bar to its
// own address autofill instead — so on the device most posters are captured on, the
// suggestions never appear at all.
export class PlaceFields {
  constructor({ places = {}, localities = {} } = {}, controller) {
    this.sources = { place: places, locality: localities }
    this.controller = controller
  }

  suggest(card, name, typed) {
    this.showMatches(card, name, this.matching(name, typed))
  }

  // Fill the tuple from a name the app already carries instead of minting a variant
  // spelling of it.
  applySuggestion(card, { name, locality, canton }) {
    this.write(card, "place", name)
    if (locality) this.write(card, "locality", locality)
    if (canton) this.write(card, "canton", canton)
    this.pin(card, "place", locality && "locality", canton && "canton")
    this.showMatches(card, "place", [])
  }

  // Fills the town and nothing else. The reason to tap one of these is that the venue is
  // NOT among the places being suggested, so writing a place here would replace the
  // contributor's reading of the poster with one nobody offered.
  applyLocality(card, { locality, canton }) {
    this.write(card, "locality", locality)
    if (canton) this.write(card, "canton", canton)
    this.pin(card, "locality")
    this.showMatches(card, "locality", [])
  }

  // A field the contributor typed in themselves is their reading of the poster,
  // whatever a suggestion put there before.
  typed(card, name, value) {
    this.markNormalized(card, name, false)
    if (name === "locality") this.fillCanton(card, value)
    this.pin(card, name)
  }

  // Matches take the row over while they stand: a ranked chip that also matches is in
  // the matches already, and one that does not is an answer to a question nobody is
  // asking any more.
  showMatches(card, name, matches) {
    const row = card?.querySelector(`[data-suggestions="${name}"]`)
    if (!row) return

    row.querySelectorAll("[data-typed]").forEach((chip) => chip.remove())
    row.querySelectorAll(".chip").forEach((chip) => { chip.hidden = matches.length > 0 })
    matches.forEach((match) => row.appendChild(this.chip(name, match)))
  }

  // Two letters before anything is offered, because one letter ranks nothing: the cap
  // would just take the first few of an alphabet.
  matching(name, typed) {
    const needle = fold(typed)
    if (needle.length < 2) return []

    const trailing = (candidate) => (fold(candidate).startsWith(needle) ? 0 : 1)
    return Object.keys(this.sources[name])
                 .filter((candidate) => fold(candidate).includes(needle))
                 .sort((a, b) => trailing(a) - trailing(b) || a.localeCompare(b))
                 .slice(0, MATCHES)
  }

  chip(name, match) {
    const chip = document.createElement("button")
    chip.type = "button"
    chip.className = "chip"
    chip.textContent = match
    chip.dataset.typed = "true"
    chip.dataset.action = `${this.controller}#${APPLY[name]}`
    Object.entries(this.chipParams(name, match)).forEach(([param, value]) => {
      chip.setAttribute(`data-${this.controller}-${param}-param`, value ?? "")
    })
    return chip
  }

  chipParams(name, match) {
    if (name === "locality") return { locality: match, canton: this.sources.locality[match] }

    const [locality, canton] = this.sources.place[match]
    return { name: match, locality: locality, canton: canton }
  }

  // Extraction computes the canton from the locality once, server-side, so a locality
  // changed here would otherwise keep the canton the one it replaced was placed in. A
  // locality matching nothing leaves the canton ALONE rather than clearing it — it may
  // hold the model's own postcode reading, which is why the field is still asked for at
  // all, or a value a human picked by hand.
  fillCanton(card, typed) {
    const canton = this.sources.locality[typed.trim()]
    if (!canton || canton === fieldValue(card, "canton")) return

    this.write(card, "canton", canton)
  }

  write(card, name, value) {
    setField(card, name, value)
    this.markNormalized(card, name, true)
  }

  // Taking a spelling the app already carries is a normalisation, not a report that the
  // model misread the poster, and the two must not land in the same number (see
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
      const target = field(card, name)
      if (target) target.dataset.pinned = "true"
    })
  }
}
