import { Controller } from "@hotwired/stimulus"
import { searchForSuggestion } from "lib/search_for"

// Connects to data-controller="filter-sheets"
//
// Drives the mobile filter sheets (app/views/events/_filter_sheets.html.erb).
// The option rows are real form inputs (name="s[]/q[]/l[]/d[]"), so committing is
// just a GET submit — same params as the inline combobox filter. This controller
// only handles presentation: opening/closing sheets, in-sheet search, the
// free-text "search for X" row, the custom date range, and removing a chip.
//
// Filters are non-destructive, so closing a sheet (× or Apply) keeps the
// selection; we navigate only when something actually changed, so tapping × on an
// untouched sheet closes instantly with no reload.
export default class extends Controller {
  static targets = ["form", "sheet", "queries", "group", "customStart", "customEnd", "customValue"]
  static values = { searchForTemplate: String, freeText: String }

  connect() {
    this.onKeydown = (event) => { if (event.key === "Escape") this.#closeOpenSheet() }
    document.addEventListener("keydown", this.onKeydown)

    // Reveal any canton that already holds a checked city/venue, so a pre-applied
    // location isn't hidden inside a collapsed group.
    this.groupTargets.forEach((group) => {
      if (group.querySelector("input:checked")) group.classList.remove("collapsed")
    })
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    document.body.classList.remove("filter-sheet-open")
  }

  open(event) {
    const sheet = this.#sheetFor(event.params.field)
    if (!sheet) return
    this.snapshot = this.#serialize(sheet)
    sheet.classList.add("sheet--open")
    sheet.setAttribute("aria-hidden", "false")
    document.body.classList.add("filter-sheet-open")
    // Move focus into the dialog for screen-reader/keyboard users, but onto the
    // close button — never the search field, so opening a sheet never summons the
    // on-screen keyboard. preventScroll keeps the page from jumping.
    sheet.querySelector(".sheet__close")?.focus({ preventScroll: true })
  }

  // × and Apply both commit (see class comment). Distinct labels, same behaviour.
  close(event) { this.#commit(event.target.closest(".sheet")) }
  apply(event) { this.#commit(event.target.closest(".sheet")) }

  // Uncheck everything in this sheet; the user then closes to commit the clear.
  clear(event) {
    const sheet = this.#sheetFor(event.params.field)
    if (!sheet) return
    sheet.querySelectorAll("input[type=checkbox]").forEach((input) => { input.checked = false })
    sheet.querySelectorAll("input[type=date]").forEach((input) => { input.value = "" })
    sheet.querySelectorAll("[data-dynamic]").forEach((row) => row.remove())
  }

  toggleGroup(event) {
    event.currentTarget.closest(".loc-group")?.classList.toggle("collapsed")
  }

  // In-sheet search: hide non-matching rows. While searching, expand groups and
  // drop those with no surviving rows; clearing the box re-collapses them.
  filter(event) {
    const sheet = event.target.closest(".sheet")
    const raw = event.target.value.trim()
    const query = raw.toLowerCase()

    sheet.querySelectorAll(".opt:not(.opt--newquery)").forEach((opt) => {
      const haystack = (opt.dataset.search || opt.textContent).toLowerCase()
      opt.classList.toggle("opt--hidden", query !== "" && !haystack.includes(query))
    })

    sheet.querySelectorAll(".loc-group").forEach((group) => {
      if (query === "") {
        group.classList.add("collapsed")
        group.classList.remove("loc-group--hidden")
      } else {
        group.classList.remove("collapsed")
        group.classList.toggle("loc-group--hidden", !group.querySelector(".opt:not(.opt--hidden)"))
      }
    })

    this.#updateNewQuery(sheet, raw)
  }

  // Free-text "Search for X" row → a checked q[] row.
  addQuery(event) {
    const row = event.currentTarget
    const value = row.dataset.value
    if (!value) return

    const exists = [...this.queriesTarget.querySelectorAll('input[name="q[]"]')]
      .some((input) => input.value === value)
    if (!exists) this.queriesTarget.prepend(this.#queryRow(value))

    const search = row.closest(".sheet").querySelector(".sheet__search-input")
    if (search) { search.value = ""; search.dispatchEvent(new Event("input", { bubbles: true })) }
  }

  // Two native date inputs → the hidden "start - end" d[] input.
  customRange() {
    const start = this.customStartTarget.value
    const end = this.customEndTarget.value
    if (start && end) {
      this.customValueTarget.value = `${start} - ${end}`
      this.customValueTarget.checked = true
    } else {
      this.customValueTarget.checked = false
    }
  }

  // Remove one applied filter from the summary row, then re-submit.
  remove(event) {
    const { name, value } = event.params
    this.formTarget.querySelectorAll(`input[name="${name}[]"]`).forEach((input) => {
      if (input.value !== String(value)) return
      input.checked = false
      input.closest("[data-dynamic]")?.remove()
    })
    // A custom-range chip also clears its date inputs so the sheet reopens empty.
    if (name === "d" && String(value).includes(" - ") && this.hasCustomStartTarget) {
      this.customStartTarget.value = ""
      this.customEndTarget.value = ""
    }
    this.#submit()
  }

  #updateNewQuery(sheet, raw) {
    const row = sheet.querySelector(".opt--newquery")
    if (!row) return

    const labels = [...sheet.querySelectorAll(".opt:not(.opt--newquery) .opt__label")]
      .map((label) => label.textContent)
    const suggestion = searchForSuggestion(raw, labels, this.searchForTemplateValue)

    if (suggestion.show) {
      row.querySelector("[data-newquery-label]").textContent = suggestion.label
      row.dataset.value = suggestion.value
      row.hidden = false
    } else {
      row.hidden = true
    }
  }

  #queryRow(value) {
    const label = document.createElement("label")
    label.className = "opt opt--query"
    label.dataset.dynamic = "true"
    label.innerHTML =
      '<input type="checkbox" name="q[]" checked>' +
      '<span class="opt__box"></span>' +
      '<span class="opt__label"></span>' +
      '<span class="opt__type"></span>'
    label.querySelector("input").value = value
    label.querySelector(".opt__label").textContent = value
    label.querySelector(".opt__type").textContent = this.freeTextValue
    return label
  }

  #commit(sheet) {
    if (!sheet) return
    const changed = this.snapshot !== undefined && this.#serialize(sheet) !== this.snapshot
    this.#closeSheet(sheet)
    if (changed) this.#submit()
  }

  #closeOpenSheet() {
    const open = this.sheetTargets.find((sheet) => sheet.classList.contains("sheet--open"))
    if (open) this.#commit(open)
  }

  #closeSheet(sheet) {
    sheet.classList.remove("sheet--open")
    sheet.setAttribute("aria-hidden", "true")
    document.body.classList.remove("filter-sheet-open")
    this.snapshot = undefined
  }

  #serialize(sheet) {
    const checked = [...sheet.querySelectorAll("input[type=checkbox]")]
      .filter((input) => input.checked)
      .map((input) => `${input.name}=${input.value}`)
      .sort()
    const dates = [...sheet.querySelectorAll("input[type=date]")].map((input) => input.value)
    return [...checked, ...dates].join("|")
  }

  #submit() {
    this.formTarget.requestSubmit()
  }

  #sheetFor(field) {
    return this.sheetTargets.find((sheet) => sheet.dataset.field === field)
  }
}
