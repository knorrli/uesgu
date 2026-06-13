import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="rule-form" on the new-rule form. Shows only the
// fields relevant to the current choices: weekday (weekly/biweekly), monthday
// (monthly), window (happening content type), and the custom-filter block
// (custom scope).
export default class extends Controller {
  static targets = ["cadence", "contentType", "scope", "weekday", "monthday", "window", "custom"]

  connect() {
    this.update()
  }

  update() {
    const cadence = this.cadenceTarget.value
    const content = this.contentTypeTarget.value
    const scope = this.scopeTarget.value

    this.show(this.weekdayTarget, cadence === "weekly" || cadence === "biweekly")
    this.show(this.monthdayTarget, cadence === "monthly")
    this.show(this.windowTarget, content === "happening")
    this.show(this.customTarget, scope === "custom")
  }

  show(target, visible) {
    if (target) target.hidden = !visible
  }
}
