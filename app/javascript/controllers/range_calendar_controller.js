import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["grid", "label"]
  static values = {
    today: String,
    selected: String,
    monthNames: Array,
    enabled: Array,
    url: String,
  }

  connect() {
    const [year, month] = (this.selectedValue || this.todayValue).split("-").map(Number)
    this.viewYear = year
    this.viewMonth = month
    this.#render()
  }

  prevMonth() { this.#shiftMonth(-1) }
  nextMonth() { this.#shiftMonth(1) }

  pick(event) {
    this.#visit(event.currentTarget.dataset.date)
  }

  navigate(event) {
    const step = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }[event.key]
    if (step === undefined) return
    const iso = event.target.dataset?.date
    if (!iso) return
    event.preventDefault()

    const next = this.#step(iso, step)
    if (!next) return
    if (next.getFullYear() !== this.viewYear || next.getMonth() + 1 !== this.viewMonth) {
      this.viewYear = next.getFullYear()
      this.viewMonth = next.getMonth() + 1
      this.#render()
    }
    this.gridTarget.querySelector(`[data-date="${this.#iso(next)}"]`)?.focus()
  }

  #selectable(iso) { return this.enabledValue.includes(iso) }

  #step(iso, step) {
    const [y, m, d] = iso.split("-").map(Number)
    for (let i = 1; ; i++) {
      const next = new Date(y, m - 1, d + step * i)
      const nextIso = this.#iso(next)
      if (this.#selectable(nextIso)) return next
      if (this.#beyondEnabled(nextIso, step)) return null
    }
  }

  #beyondEnabled(iso, step) {
    const dates = this.enabledValue
    if (dates.length === 0) return true
    return step > 0 ? iso > dates[dates.length - 1] : iso < dates[0]
  }

  #visit(iso) {
    const url = new URL(this.urlValue, window.location.href)
    url.searchParams.set("day", iso)
    Turbo.visit(url.toString())
  }

  #shiftMonth(delta) {
    let month = this.viewMonth + delta
    let year = this.viewYear
    if (month < 1) { month = 12; year -= 1 }
    if (month > 12) { month = 1; year += 1 }
    this.viewMonth = month
    this.viewYear = year
    this.#render()
  }

  #render() {
    this.labelTarget.textContent = `${this.monthNamesValue[this.viewMonth]} ${this.viewYear}`

    const first = new Date(this.viewYear, this.viewMonth - 1, 1)
    const daysBeforeMonday = (first.getDay() + 6) % 7
    const cells = []
    for (let i = 0; i < 42; i++) {
      const date = new Date(this.viewYear, this.viewMonth - 1, 1 - daysBeforeMonday + i)
      const iso = this.#iso(date)
      const classes = ["range-cal__day"]
      if (date.getMonth() + 1 !== this.viewMonth) classes.push("is-other-month")
      if (iso === this.todayValue) classes.push("is-today")
      if (iso < this.todayValue) classes.push("is-past")
      if (iso === this.selectedValue) classes.push("is-selected")
      const label = `${date.getDate()}. ${this.monthNamesValue[date.getMonth() + 1]} ${date.getFullYear()}`
      cells.push(
        `<button type="button" role="gridcell" data-date="${iso}" aria-label="${label}"` +
          `${this.#selectable(iso) ? "" : " disabled"}` +
          ` class="${classes.join(" ")}"` +
          ` data-action="click->range-calendar#pick">` +
          `${date.getDate()}</button>`
      )
    }
    this.gridTarget.innerHTML = cells.join("")
  }

  #iso(date) {
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    return `${date.getFullYear()}-${month}-${day}`
  }
}
