import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="rule-form" on the alert form. The schedule keys
// off the window select: with a window selected the cadence is DERIVED from it
// (WINDOW_RHYTHM, passed as rhythms-value), so the cadence picker is hidden and
// the model forces the cadence; without a window the user picks the cadence
// freely. Either way the weekday picker shows for weekly/biweekly rhythms and
// the day-of-month picker for monthly. (The CSS that makes [hidden] win over
// .flex lives in notification_rules.css.)
export default class extends Controller {
  static targets = ["window", "cadence", "cadenceField", "weekday", "monthday"]
  static values = { rhythms: Object }

  connect() {
    this.update()
  }

  update() {
    const windowed = this.hasWindowTarget && this.windowTarget.value !== ""
    const rhythm = windowed ? this.rhythmsValue[this.windowTarget.value] : this.cadenceTarget.value

    this.show(this.cadenceFieldTarget, !windowed)
    this.show(this.weekdayTarget, rhythm === "weekly" || rhythm === "biweekly")
    this.show(this.monthdayTarget, rhythm === "monthly")
  }

  show(target, visible) {
    if (target) target.hidden = !visible
  }

  // Snap the entered time to the nearest quarter hour on blur — the scheduler
  // sweeps quarter-hourly, so finer times would just fire late. Mirrors the
  // server-side snap; here it gives immediate feedback (18:04 → 18:00) instead
  // of a blocking step= validation error.
  snapTime(event) {
    const input = event.target
    if (!input.value) return

    const [hours, minutes] = input.value.split(":").map(Number)
    let snapped = Math.round((hours * 60 + minutes) / 15) * 15
    if (snapped >= 1440) snapped -= 15

    const hh = String(Math.floor(snapped / 60)).padStart(2, "0")
    const mm = String(snapped % 60).padStart(2, "0")
    input.value = `${hh}:${mm}`
  }
}
