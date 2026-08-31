import { Controller } from "@hotwired/stimulus"
import { PlaceFields } from "lib/capture/place_fields"

// The hand-entry form. It shares its fields with a review card (see
// captures/_event_fields) but not that card's controller: hand entry has no poster to
// read against, no queue, and no sibling card to carry a corrected venue to — so what
// the two screens have in common is the collaborator, not the controller.
//
// Connects to data-controller="manual-capture".
export default class extends Controller {
  static values = { places: Object, localities: Object }

  initialize() {
    this.fields = new PlaceFields({ places: this.placesValue, localities: this.localitiesValue },
                                  this.identifier)
  }

  applySuggestion(event) {
    this.fields.applySuggestion(this.element, event.params)
  }

  applyLocality(event) {
    this.fields.applyLocality(this.element, event.params)
  }

  suggestPlaces(event) {
    this.fields.suggest(this.element, "place", event.target.value)
  }

  suggestLocalities(event) {
    this.fields.suggest(this.element, "locality", event.target.value)
  }

  typed(event) {
    this.fields.typed(this.element, event.target.name, event.target.value)
  }
}
