import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["value", "grid", "label", "summary"]
  static values = {
    today: String,      // server "today" ISO — drives the today-pill + default month
    start: String,      // pre-applied range start ISO (or "")
    end: String,        // pre-applied range end ISO (or "")
    monthNames: Array,  // I18n date.month_names: [null, "Januar", … "Dezember"]
  }

  connect() {
    this.start = this.startValue || null
    this.end = this.endValue || null
    this.hover = null
    const [year, month] = (this.start || this.todayValue).split("-").map(Number)
    this.viewYear = year
    this.viewMonth = month // 1–12
    this.#render()
  }

  prevMonth() { this.#shiftMonth(-1) }
  nextMonth() { this.#shiftMonth(1) }

  pick(event) {
    const iso = event.currentTarget.dataset.date
    if (!this.start || this.end) {
      this.start = iso
      this.end = null
    } else if (iso < this.start) {
      this.end = this.start
      this.start = iso
    } else {
      this.end = iso
    }
    this.hover = null
    this.#commitValue()
    this.#paint()
  }

  preview(event) {
    if (!this.start || this.end) return
    this.hover = event.currentTarget.dataset.date
    this.#paint()
  }

  clearPreview() {
    if (this.hover === null) return
    this.hover = null
    this.#paint()
  }

  navigate(event) {
    const step = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }[event.key]
    if (step === undefined) return
    const iso = event.target.dataset?.date
    if (!iso) return
    event.preventDefault()

    const [y, m, d] = iso.split("-").map(Number)
    const next = new Date(y, m - 1, d + step)
    if (next.getFullYear() !== this.viewYear || next.getMonth() + 1 !== this.viewMonth) {
      this.viewYear = next.getFullYear()
      this.viewMonth = next.getMonth() + 1
      this.#render()
    }
    this.gridTarget.querySelector(`[data-date="${this.#iso(next)}"]`)?.focus()
  }

  reset() {
    this.start = null
    this.end = null
    this.hover = null
    this.valueTarget.checked = false
    this.valueTarget.value = ""
    this.#paint()
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

  #commitValue() {
    if (this.start && this.end) {
      this.valueTarget.value = `${this.start} - ${this.end}`
      this.valueTarget.checked = true
    } else {
      this.valueTarget.checked = false
    }
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }

  #render() {
    this.labelTarget.textContent = `${this.monthNamesValue[this.viewMonth]} ${this.viewYear}`

    const first = new Date(this.viewYear, this.viewMonth - 1, 1)
    const lead = (first.getDay() + 6) % 7 // leading blanks for a Monday-first week
    const cells = []
    for (let i = 0; i < 42; i++) {
      const date = new Date(this.viewYear, this.viewMonth - 1, 1 - lead + i)
      const iso = this.#iso(date)
      const otherMonth = date.getMonth() + 1 !== this.viewMonth
      const label = `${date.getDate()}. ${this.monthNamesValue[date.getMonth() + 1]} ${date.getFullYear()}`
      cells.push(
        `<button type="button" role="gridcell" data-date="${iso}" aria-label="${label}"` +
          ` class="range-cal__day${otherMonth ? " is-other-month" : ""}${iso === this.todayValue ? " is-today" : ""}"` +
          ` data-action="click->range-calendar#pick mouseenter->range-calendar#preview mouseleave->range-calendar#clearPreview">` +
          `${date.getDate()}</button>`
      )
    }
    this.gridTarget.innerHTML = cells.join("")
    this.#paint()
  }

  #paint() {
    const lo = this.start
    let hi = this.end || (this.start && !this.end ? this.hover : null)
    let [a, b] = hi && hi < lo ? [hi, lo] : [lo, hi]

    this.gridTarget.querySelectorAll(".range-cal__day").forEach((cell) => {
      const iso = cell.dataset.date
      cell.classList.remove("is-start", "is-end", "is-in-range")
      if (!this.start) return
      if (!b) {
        if (iso === a) cell.classList.add("is-start")
      } else if (iso === a) {
        cell.classList.add("is-start")
      } else if (iso === b) {
        cell.classList.add("is-end")
      } else if (iso > a && iso < b) {
        cell.classList.add("is-in-range")
      }
    })

    this.#renderSummary()
  }

  #renderSummary() {
    const fmt = (iso) => { const [y, m, d] = iso.split("-"); return `${d}.${m}.${y}` }
    if (!this.start) {
      this.summaryTarget.textContent = ""
    } else if (!this.end) {
      this.summaryTarget.textContent = `${fmt(this.start)} → …`
    } else if (this.start === this.end) {
      this.summaryTarget.textContent = fmt(this.start)
    } else {
      this.summaryTarget.textContent = `${fmt(this.start)} → ${fmt(this.end)}`
    }
  }

  #iso(date) {
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    return `${date.getFullYear()}-${month}-${day}`
  }
}
