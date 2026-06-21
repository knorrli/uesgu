import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="saved-filter-form" on the alert form. The schedule keys
// off the window picked in the When sheet (a single-select d[] preset): with a
// window selected the cadence is DERIVED from it (WINDOW_RHYTHM, passed as
// rhythms-value), so the cadence picker is hidden and the model forces the
// cadence; without a window the user picks the cadence freely. Either way the
// weekday picker shows for weekly/biweekly rhythms and the day-of-month picker for
// monthly. #update runs on any change bubbling up from the form (the form's
// data-action), so it reacts to the panel the moment a preset is ticked. (The CSS
// that makes [hidden] win over .flex lives in saved_filters.css.)
export default class extends Controller {
  static targets = ["cadence", "cadenceField", "weekday", "monthday"]
  static values = { rhythms: Object }

  connect() {
    this.update()
  }

  update() {
    const window = this.#window()
    const windowed = window !== ""
    const rhythm = windowed ? this.rhythmsValue[window] : this.cadenceTarget.value

    this.show(this.cadenceFieldTarget, !windowed)
    this.show(this.weekdayTarget, rhythm === "weekly" || rhythm === "biweekly")
    this.show(this.monthdayTarget, rhythm === "monthly")
  }

  show(target, visible) {
    if (target) target.hidden = !visible
  }

  // The selected relative window, "" when none — the checked preset in the When
  // sheet (enforceSingle keeps it to one). A custom-range value never occurs here:
  // the editor's When sheet renders presets only.
  #window() {
    const checked = this.element.querySelector('.sheet[data-field="when"] input[name="d[]"]:checked')
    return checked ? checked.value : ""
  }
}
