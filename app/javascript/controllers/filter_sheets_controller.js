import { Controller } from "@hotwired/stimulus"
import { searchForSuggestion } from "lib/search_for"

export default class extends Controller {
  static targets = ["form", "sheet", "queries", "group"]
  static values = { searchForTemplate: String, searchAnything: String, submitOnApply: { type: Boolean, default: true } }

  connect() {
    this.onKeydown = (event) => { if (event.key === "Escape") this.#closeOpenSheet() }
    document.addEventListener("keydown", this.onKeydown)

    this.onClickOutside = (event) => {
      const open = this.sheetTargets.find((sheet) => sheet.classList.contains("sheet--open"))
      if (!open || open.contains(event.target) || event.target.closest(".filter-trigger")) return
      this.#commit(open)
    }
    document.addEventListener("click", this.onClickOutside)

    this.onFetchError = (event) => {
      const frame = event.target.closest?.("turbo-frame[data-src]")
      frame?.removeAttribute("src")
    }
    this.element.addEventListener("turbo:fetch-request-error", this.onFetchError)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onClickOutside)
    this.element.removeEventListener("turbo:fetch-request-error", this.onFetchError)
    document.body.classList.remove("filter-sheet-open")
  }

  groupTargetConnected(group) {
    if (group.querySelector("input:checked")) group.classList.remove("collapsed")
  }

  open(event) {
    const sheet = this.#sheetFor(event.params.field)
    if (!sheet) return
    if (sheet.classList.contains("sheet--open")) { this.#commit(sheet); return }
    this.#loadOptions(sheet)
    this.sheetTargets.forEach((other) => { if (other !== sheet) this.#closeSheet(other) })
    this.snapshot = this.#serialize(sheet)
    sheet.classList.add("sheet--open")
    sheet.setAttribute("aria-hidden", "false")
    document.body.classList.add("filter-sheet-open")
    const search = sheet.querySelector(".sheet__search-input")
    const target = (this.#isDesktop() && search) ? search : sheet.querySelector(".sheet__close")
    target?.focus({ preventScroll: true })
    this.#updateNewQuery(sheet, sheet.querySelector(".sheet__search-input")?.value.trim() || "")
  }

  close(event) { this.#commit(event.target.closest(".sheet")) }
  apply(event) { this.#commit(event.target.closest(".sheet")) }

  clear(event) {
    const sheet = this.#sheetFor(event.params.field)
    if (!sheet) return
    sheet.querySelectorAll("input[type=checkbox]").forEach((input) => { input.checked = false })
    sheet.querySelectorAll(".range-cal").forEach((cal) => cal.dispatchEvent(new CustomEvent("range-calendar:reset")))
    sheet.querySelectorAll("[data-dynamic]").forEach((row) => row.remove())
  }

  toggleGroup(event) {
    event.currentTarget.closest(".loc-group")?.classList.toggle("collapsed")
  }

  enforceSingle(event) {
    const input = event.target
    if (!input.checked) return
    input.closest(".sheet").querySelectorAll('input[type="checkbox"]').forEach((other) => {
      if (other !== input) other.checked = false
    })
  }

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

  addQuery(event) {
    const row = event.currentTarget
    const search = row.closest(".sheet").querySelector(".sheet__search-input")
    const value = row.dataset.value
    if (!value) { search?.focus(); return }

    this.#addQueryValue(value)

    if (search) { search.value = ""; search.dispatchEvent(new Event("input", { bubbles: true })) }
  }

  commitTyped(event) {
    if (event.key !== "Enter") return
    event.preventDefault()

    const input = event.target
    const { value, blank } = searchForSuggestion(input.value, this.searchForTemplateValue, this.searchAnythingValue)
    if (!blank) {
      this.#addQueryValue(value)
      input.value = ""
    }
    this.#submit()
    if (!this.submitOnApplyValue) this.#refreshTrigger(input.closest(".sheet"))
  }

  remove(event) {
    const { name, value } = event.params
    this.formTarget.querySelectorAll(`input[name="${name}[]"]`).forEach((input) => {
      if (input.value !== String(value)) return
      input.checked = false
      input.closest("[data-dynamic]")?.remove()
    })
    if (name === "d" && String(value).includes(" - ")) {
      this.element.querySelectorAll(".range-cal").forEach((cal) => cal.dispatchEvent(new CustomEvent("range-calendar:reset")))
    }
    this.#submit()
  }

  #loadOptions(sheet) {
    const frame = sheet.querySelector("turbo-frame[data-src]")
    if (!frame || frame.hasAttribute("src")) return
    frame.setAttribute("src", frame.dataset.src)
  }

  #updateNewQuery(sheet, raw) {
    const row = sheet.querySelector(".opt--newquery")
    if (!row) return

    const suggestion = searchForSuggestion(raw, this.searchForTemplateValue, this.searchAnythingValue)
    row.querySelector("[data-newquery-label]").textContent = suggestion.label
    row.dataset.value = suggestion.value
    row.hidden = false
  }

  #addQueryValue(value) {
    const exists = [...this.queriesTarget.querySelectorAll('input[name="q[]"]')]
      .some((input) => input.value === value)
    if (exists) return
    this.queriesTarget.prepend(this.#queryRow(value))
    this.#notifyChanged()
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
    this.#stagePendingQuery(sheet)
    const changed = this.snapshot !== undefined && this.#serialize(sheet) !== this.snapshot
    this.#closeSheet(sheet)
    if (!changed) return
    this.#submit()
    if (!this.submitOnApplyValue) this.#refreshTrigger(sheet)
  }

  #stagePendingQuery(sheet) {
    if (!this.hasQueriesTarget || !sheet.querySelector(".opt--newquery")) return
    const input = sheet.querySelector(".sheet__search-input")
    if (!input || !input.value.trim()) return

    if (this.#genresToggled(sheet)) { input.value = ""; return }

    const { value, blank } = searchForSuggestion(input.value, this.searchForTemplateValue, this.searchAnythingValue)
    if (blank) return
    this.#addQueryValue(value)
    input.value = ""
  }

  #genresToggled(sheet) {
    const genres = (serialized) =>
      serialized.split("|").filter((pair) => pair.startsWith("g[]=")).sort().join("|")
    const opened = this.snapshot === undefined ? "" : genres(this.snapshot)
    return genres(this.#serialize(sheet)) !== opened
  }

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
    return [...sheet.querySelectorAll("input[type=checkbox]")]
      .filter((input) => input.checked)
      .map((input) => `${input.name}=${input.value}`)
      .sort()
      .join("|")
  }

  #submit() {
    if (!this.submitOnApplyValue) return
    this.formTarget.requestSubmit()
  }

  #notifyChanged() {
    this.formTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  #sheetFor(field) {
    return this.sheetTargets.find((sheet) => sheet.dataset.field === field)
  }

  #isDesktop() {
    return window.matchMedia("(min-width: 600px)").matches
  }
}
