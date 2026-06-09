import { Controller } from "@hotwired/stimulus"
import HwComboboxController from "controllers/hw_combobox_controller"

// Add a value to a multiselect combobox from outside it. Used by the genre
// editor's quick-select suggestions so a click populates the styles combobox
// (composing with the dropdown) instead of committing immediately. Mirrors the
// way filter_controller already extends this controller.
HwComboboxController.prototype.addValueExternally = function (value) {
  if (this._fieldValue.has(String(value))) return

  this._addToFieldValue(value)
  this._requestChips(value)
}

// Connects to data-controller="style-picker" wrapping the editor. Suggestion
// buttons call #add with the style id; the combobox is found within the wrapper.
export default class extends Controller {
  add(event) {
    const combobox = this.element.querySelector('[data-controller~="hw-combobox"]')
    if (!combobox) return

    const controller = this.application.getControllerForElementAndIdentifier(combobox, "hw-combobox")
    controller?.addValueExternally(event.params.styleId)
  }
}
