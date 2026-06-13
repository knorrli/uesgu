import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="rule-form" on the new-alert schedule form. Shows
// the weekday picker only for weekly/biweekly cadences, and the day-of-month
// picker only for monthly. (The CSS that makes [hidden] win over .flex lives in
// notification_rules.css.)
export default class extends Controller {
  static targets = ["cadence", "weekday", "monthday"]

  connect() {
    this.update()
  }

  update() {
    const cadence = this.cadenceTarget.value
    this.show(this.weekdayTarget, cadence === "weekly" || cadence === "biweekly")
    this.show(this.monthdayTarget, cadence === "monthly")
  }

  show(target, visible) {
    if (target) target.hidden = !visible
  }
}
