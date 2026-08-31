import { fieldValue, pinned, setField } from "lib/capture/place_fields"

const PLACE_FIELDS = ["place", "locality", "canton"]

export class PlaceCarry {
  constructor() {
    this.shared = new Map()
  }

  share(card, cards) {
    const row = card?.closest(".capture-row")
    if (!row) return

    const shared = this.shared.get(row.id) ?? { values: {}, answered: new Set() }
    PLACE_FIELDS.forEach((name) => {
      const value = fieldValue(card, name)
      if (!value || (shared.answered.has(name) && !pinned(card, name))) return

      shared.values[name] = value
      if (pinned(card, name)) shared.answered.add(name)
    })
    this.shared.set(row.id, shared)

    cards.filter((sibling) => sibling.closest(".capture-row") === row)
         .forEach((sibling) => this.fill(sibling, shared))
  }

  clear() {
    this.shared.clear()
  }

  fill(card, shared) {
    if (card.dataset.state !== "open") return

    PLACE_FIELDS.forEach((name) => {
      const value = shared.values[name]
      if (!value || pinned(card, name)) return
      if (fieldValue(card, name) && !shared.answered.has(name)) return

      setField(card, name, value)
    })
  }
}
