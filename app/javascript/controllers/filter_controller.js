import { Controller } from "@hotwired/stimulus"
import { searchForSuggestion } from "lib/search_for"

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
    'searchFor'
  ];

  // The "What" combobox already accepts free text (name_when_new: 'query'), but
  // the gem shows no hint that you can. Mirror the mobile sheet: drop a
  // "Search for «X»" row into the styles dropdown and reveal it (via the same
  // shared logic) when the typed text matches no style. The row carries no
  // filterable attribute, so the gem never treats it as a real option.
  connect() {
    this.#setupSearchFor()
  }

  disconnect() {
    if (this.styleInput && this.onStyleInput) {
      this.styleInput.removeEventListener('input', this.onStyleInput)
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

  // Commit the "Search for «X»" row as a free-text query. Same destination as
  // typing the text and pressing enter (which the gem's name_when_new flow
  // already handles for keyboard users) — this is just the pointer affordance.
  addSearchQuery() {
    const value = this.searchForTarget.dataset.value;
    if (value) this.#addComboboxValue(value, this.queriesInputTarget);
  }

  #setupSearchFor() {
    if (!this.hasSearchForTarget || !this.hasStylesInputTarget) return;

    const fieldset = this.stylesInputTarget.closest('fieldset');
    this.styleListbox = fieldset?.querySelector('[role="listbox"]');
    this.styleInput = fieldset?.querySelector('input[role="combobox"]');
    if (!this.styleListbox || !this.styleInput) return;

    // Move the row to the top of the dropdown so it rides the listbox's
    // open/close and scroll, and sits above the options — matching the mobile
    // sheet, where the free-text row is the first item.
    this.styleListbox.prepend(this.searchForTarget);

    this.onStyleInput = () => this.#refreshSearchFor();
    this.styleInput.addEventListener('input', this.onStyleInput);
  }

  #refreshSearchFor() {
    const labels = [...this.styleListbox.querySelectorAll('[role="option"][data-value]')]
      .map((option) => option.dataset.value);
    const suggestion = searchForSuggestion(
      this.styleInput.value,
      labels,
      this.searchForTarget.dataset.searchForTemplate
    );

    if (suggestion.show) {
      this.searchForTarget.querySelector('[data-search-for-label]').textContent = suggestion.label;
      this.searchForTarget.dataset.value = suggestion.value;
      this.searchForTarget.hidden = false;
    } else {
      this.searchForTarget.hidden = true;
    }
  }

  #clearComboboxInput(comboboxId) {
    // Some selection events arrive with a blank fieldName; guard so we never
    // call getElementById('') (logs a console warning) or deref a missing node.
    const input = comboboxId && document.getElementById(comboboxId);
    if (input) input.value = '';
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
