import { Controller } from "@hotwired/stimulus"
import { PlaceFields } from "lib/capture/place_fields"

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

  typedPlace(event) {
    this.fields.typed(this.element, event.target.name, event.target.value)
  }
}
