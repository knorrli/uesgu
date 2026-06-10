import { Controller } from "@hotwired/stimulus"

// Override "lock-in" functionality of hotwire combobox
// That way, it feels more like a select tag...
import HwComboboxController from "controllers/hw_combobox_controller"

// Prevent filtering of the list when closing the listbox
HwComboboxController.prototype._lockInSelection = function() {
  // if (this._shouldLockInSelection) {
  //   this._forceSelectionAndFilter(this._ensurableOption, "hw:lockInSelection");
  // }
}
// Do not filter when forcing selection
HwComboboxController.prototype._forceSelectionAndFilter = function(option, inputType) {
  this._forceSelectionWithoutFiltering(option);
  // this._filter(inputType);
}

// Connects to data-controller="filter"
export default class extends Controller {

  static targets = [
    'form',
    'comboboxInput',
    'queriesInput',
    'stylesInput',
    'locationsInput',
    'dateRangesInput',

    'queryHandle'
  ];

  switchQueryHandle(event) {
    // Swap only the Phosphor glyph class; the ph base weight stays put.
    if (event.target.value) {
      this.queryHandleTarget.classList.remove(this.queryHandleTarget.dataset.defaultHandle);
      this.queryHandleTarget.classList.add('ph-magnifying-glass');
    } else {
      this.queryHandleTarget.classList.add(this.queryHandleTarget.dataset.defaultHandle);
      this.queryHandleTarget.classList.remove('ph-magnifying-glass');
    }
  }

  addStyleOrQuery(event) {
    if (event.detail.fieldName == event.target.dataset.hwComboboxNameWhenNewValue) {
      const originalInput = document.querySelector(`[name="${event.detail.fieldName}"]`);
      originalInput.setAttribute('name', event.target.dataset.hwComboboxOriginalNameValue);
      this.#addComboboxValue(event.detail.value, this.queriesInputTarget);
    } else {
      this.#clearComboboxInput(event.detail.fieldName);
      this.#addComboboxValue(event.detail.value, this.stylesInputTarget);
    }
  }

  addLocation(event) {
    this.#clearComboboxInput(event.detail.fieldName);
    this.#addComboboxValue(event.detail.value, this.locationsInputTarget);
  }

  addDateRange(event) {
    this.#clearComboboxInput(event.detail.fieldName);
    this.#addComboboxValue(event.detail.value, this.dateRangesInputTarget);
  }

  removeStyle(event) {
    this.#removeComboboxValue(event.params.value, this.stylesInputTarget);
  }

  removeQuery(event) {
    this.#removeComboboxValue(event.params.value, this.queriesInputTarget);
  }

  removeLocation(event) {
    this.#removeComboboxValue(event.params.value, this.locationsInputTarget);
  }

  removeDateRange(event) {
    this.#removeComboboxValue(event.params.value, this.dateRangesInputTarget);
  }

  #clearComboboxInput(comboboxId) {
    document.getElementById(comboboxId).value = '';
  }

  #addComboboxValue(value, target) {
    const existingValues = JSON.parse(target.dataset.existingValues);
    target.dataset.existingValues = JSON.stringify([...existingValues, value]);
    this.#submitForm();
  }

  #removeComboboxValue(value, target) {
    const existingValues = JSON.parse(target.dataset.existingValues);
    const filteredValues = existingValues.filter((existingValue) => existingValue != value);
    target.dataset.existingValues = JSON.stringify(filteredValues);

    this.#submitForm();
  }

  #submitForm() {
    this.comboboxInputTargets.forEach((input) => {
      input.value = JSON.parse(input.dataset.existingValues);
    });

    this.formTarget.requestSubmit();
  }
}
