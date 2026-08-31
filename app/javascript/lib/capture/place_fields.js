const MATCHES = 6

export const fold = (value) => value.trim().toLowerCase().normalize("NFD").replace(/\p{Diacritic}/gu, "")

export const field = (card, name) => card?.querySelector(`[name="${name}"]`)

export const fieldValue = (card, name) => field(card, name)?.value ?? ""

export const pinned = (card, name) => field(card, name)?.dataset.pinned === "true"

export const setField = (card, name, value) => {
  const target = field(card, name)
  if (target) target.value = value
}

const APPLY = { place: "applySuggestion", locality: "applyLocality" }

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

  applySuggestion(card, { name, locality, canton }) {
    this.write(card, "place", name)
    if (locality) this.write(card, "locality", locality)
    if (canton) this.write(card, "canton", canton)
    this.pin(card, "place", locality && "locality", canton && "canton")
    this.showMatches(card, "place", [])
  }

  applyLocality(card, { locality, canton }) {
    this.write(card, "locality", locality)
    if (canton) this.write(card, "canton", canton)
    this.pin(card, "locality")
    this.showMatches(card, "locality", [])
  }

  typed(card, name, value) {
    this.markNormalized(card, name, false)
    if (name === "locality") this.fillCanton(card, value)
    this.pin(card, name)
  }

  showMatches(card, name, matches) {
    const row = card?.querySelector(`[data-suggestions="${name}"]`)
    if (!row) return

    row.querySelectorAll("[data-typed]").forEach((chip) => chip.remove())
    row.querySelectorAll(".chip").forEach((chip) => { chip.hidden = matches.length > 0 })
    matches.forEach((match) => row.appendChild(this.chip(name, match)))
  }

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

  fillCanton(card, typed) {
    const canton = this.sources.locality[typed.trim()]
    if (!canton || canton === fieldValue(card, "canton")) return

    this.write(card, "canton", canton)
  }

  write(card, name, value) {
    setField(card, name, value)
    this.markNormalized(card, name, true)
  }

  markNormalized(card, name, normalized) {
    const flag = card?.querySelector(`[name="normalized_${name}"]`)
    if (flag) flag.value = normalized ? "1" : ""
  }

  pin(card, ...names) {
    const claimed = names.includes("locality") ? [...names, "canton"] : names
    claimed.filter(Boolean).forEach((name) => {
      const target = field(card, name)
      if (target) target.dataset.pinned = "true"
    })
  }
}
