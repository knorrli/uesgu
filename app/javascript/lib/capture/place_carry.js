import { fieldValue, pinned, setField } from "lib/capture/place_fields"

// Several acts on one poster share a venue; the date and time are what differ, so only
// this tuple carries between the candidates off one input.
const PLACE_FIELDS = ["place", "locality", "canton"]

// The place tuple as it moves around one input's cards. Filling those fields and
// offering names for them is PlaceFields, which the hand-entry screen mounts on its own
// — a form holding one event has no sibling to carry anything to.
//
// `cards` is passed in at every entry point: which cards are on screen is the
// controller's to know, and this only needs the siblings of the one being acted on.
export class PlaceCarry {
  constructor() {
    this.shared = new Map()
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

  // Completes what a card never printed, and carries a correction across the ones that
  // did: one poster is one venue in one town, so a value the model read wrong is wrong on
  // every card off it. Only an answer corrects — one model reading must not overwrite
  // another, which is what a bill across two halls comes down to.
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
