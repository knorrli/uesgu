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
  // submitOnApply: the events filter navigates on every apply (live listing). The
  // rule editor sets it false — picks stage into the form as checked inputs and
  // commit only on the explicit Save, so we refresh the trigger counts client-side
  // instead of round-tripping.
  static values = { searchForTemplate: String, searchAnything: String, submitOnApply: { type: Boolean, default: true } }

  connect() {
    this.onKeydown = (event) => { if (event.key === "Escape") this.#closeOpenSheet() }
    document.addEventListener("keydown", this.onKeydown)

    // Click-outside-to-close: on desktop the open panel is dismissed by clicking
    // anywhere off it (and off its trigger, which toggles itself — see open()). On
    // mobile the sheet is full-screen, so there is no "outside" and this never fires.
    this.onClickOutside = (event) => {
      const open = this.sheetTargets.find((sheet) => sheet.classList.contains("sheet--open"))
      if (!open || open.contains(event.target) || event.target.closest(".filter-trigger")) return
      this.#commit(open)
    }
    document.addEventListener("click", this.onClickOutside)

    // Reveal any canton that already holds a checked city/venue, so a pre-applied
    // location isn't hidden inside a collapsed group.
    this.groupTargets.forEach((group) => {
      if (group.querySelector("input:checked")) group.classList.remove("collapsed")
    })
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onClickOutside)
    document.body.classList.remove("filter-sheet-open")
  }

  open(event) {
    const sheet = this.#sheetFor(event.params.field)
    if (!sheet) return
    // Toggle: clicking the trigger of an already-open panel closes it.
    if (sheet.classList.contains("sheet--open")) { this.#commit(sheet); return }
    // Desktop shows panels inline, so a second trigger could open a second panel.
    // Hide any already-open one WITHOUT committing — its checkbox state persists in
    // the form and applies on the next submit, so nothing is lost. (On mobile only
    // one sheet is ever reachable, so this loop is a no-op there.)
    this.sheetTargets.forEach((other) => { if (other !== sheet) this.#closeSheet(other) })
    this.snapshot = this.#serialize(sheet)
    sheet.classList.add("sheet--open")
    sheet.setAttribute("aria-hidden", "false")
    document.body.classList.add("filter-sheet-open")
    // Move focus into the dialog for screen-reader/keyboard users. On DESKTOP
    // (inline dropdown panel) focus the search field so you can type straight away;
    // on MOBILE focus the close button instead — never the search field, so opening
    // a sheet never summons the on-screen keyboard. preventScroll keeps the page put.
    const search = sheet.querySelector(".sheet__search-input")
    const target = (this.#isDesktop() && search) ? search : sheet.querySelector(".sheet__close")
    target?.focus({ preventScroll: true })
    // Show the free-text affordance straight away (blank "type to search" hint
    // on the What sheet; a no-op on sheets without the row).
    this.#updateNewQuery(sheet, sheet.querySelector(".sheet__search-input")?.value.trim() || "")
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

  // Free-text "Search for X" row → a checked q[] row. When it's still the blank
  // "type to search" hint (no value yet), people tap it expecting it to focus the
  // search field and start typing — so do exactly that (the tap is a user gesture,
  // so the mobile keyboard opens) rather than no-op.
  addQuery(event) {
    const row = event.currentTarget
    const search = row.closest(".sheet").querySelector(".sheet__search-input")
    const value = row.dataset.value
    if (!value) { search?.focus(); return }

    const exists = [...this.queriesTarget.querySelectorAll('input[name="q[]"]')]
      .some((input) => input.value === value)
    if (!exists) this.queriesTarget.prepend(this.#queryRow(value))

    if (search) { search.value = ""; search.dispatchEvent(new Event("input", { bubbles: true })) }
  }

  // Enter / the keyboard's search key on the What field commits the typed query
  // straight away — no need to tap the "search for X" row first. Mirrors addQuery,
  // then submits. Wired only on the What field (it owns the free-text concept);
  // preventDefault stops the input's implicit form submit, which would otherwise
  // reload without the typed text (the field carries no name of its own).
  commitTyped(event) {
    if (event.key !== "Enter") return
    event.preventDefault()

    const input = event.target
    const { value, blank } = searchForSuggestion(input.value, this.searchForTemplateValue, this.searchAnythingValue)
    if (!blank) {
      const exists = [...this.queriesTarget.querySelectorAll('input[name="q[]"]')]
        .some((row) => row.value === value)
      if (!exists) this.queriesTarget.prepend(this.#queryRow(value))
      input.value = ""
    }
    this.#submit()
    if (!this.submitOnApplyValue) this.#refreshTrigger(input.closest(".sheet"))
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

    const suggestion = searchForSuggestion(raw, this.searchForTemplateValue, this.searchAnythingValue)
    row.querySelector("[data-newquery-label]").textContent = suggestion.label
    row.dataset.value = suggestion.value
    row.hidden = false
  }

  #queryRow(value) {
    const label = document.createElement("label")
    label.className = "opt opt--query"
    label.dataset.dynamic = "true"
    label.innerHTML =
      '<input type="checkbox" name="q[]" checked>' +
      '<span class="opt__box"></span>' +
      '<span class="opt__label"></span>'
    label.querySelector("input").value = value
    label.querySelector(".opt__label").textContent = value
    return label
  }

  #commit(sheet) {
    if (!sheet) return
    const changed = this.snapshot !== undefined && this.#serialize(sheet) !== this.snapshot
    this.#closeSheet(sheet)
    if (!changed) return
    this.#submit()
    if (!this.submitOnApplyValue) this.#refreshTrigger(sheet)
  }

  // Update a trigger's label + count from its sheet's checked rows — the live
  // feedback the events filter gets from a server re-render, done client-side for
  // the no-submit (rule editor) path.
  #refreshTrigger(sheet) {
    const trigger = this.element.querySelector(`.filter-trigger[data-filter-sheets-field-param="${sheet.dataset.field}"]`)
    if (!trigger) return

    const labels = [...sheet.querySelectorAll("input[type=checkbox]:checked")]
      .map((input) => input.closest(".opt")?.querySelector(".opt__label")?.textContent.trim())
      .filter(Boolean)
    const labelEl = trigger.querySelector(".filter-trigger__label")
    let badge = trigger.querySelector(".badge")

    if (labels.length === 0) {
      labelEl.classList.add("is-empty")
      labelEl.textContent = trigger.dataset.emptyLabel || ""
      badge?.remove()
      return
    }

    labelEl.classList.remove("is-empty")
    labelEl.textContent = labels[0]
    if (labels.length > 1) {
      const more = document.createElement("span")
      more.className = "filter-trigger__more"
      more.textContent = ` +${labels.length - 1}`
      labelEl.appendChild(more)
    }
    if (!badge) {
      badge = document.createElement("span")
      badge.className = "badge"
      labelEl.after(badge)
    }
    badge.textContent = labels.length
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
    if (!this.submitOnApplyValue) return
    this.formTarget.requestSubmit()
  }

  #sheetFor(field) {
    return this.sheetTargets.find((sheet) => sheet.dataset.field === field)
  }

  // Desktop = the inline dropdown-panel layout (≥600px, matching the CSS breakpoint
  // where the full-screen sheet becomes a panel). Drives autofocus: search on
  // desktop, close button on mobile (no surprise keyboard).
  #isDesktop() {
    return window.matchMedia("(min-width: 600px)").matches
  }
}
