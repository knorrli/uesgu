import { Controller } from "@hotwired/stimulus"

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

  #window() {
    const checked = this.element.querySelector('.sheet[data-field="when"] input[name="d[]"]:checked')
    return checked ? checked.value : ""
  }
}
