import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["title", "save", "player", "switcher", "previous", "next", "position"]

  connect() {
    this.prepareRender = this.prepareRender.bind(this)
    this.keepOutOfCache = this.keepOutOfCache.bind(this)
    document.addEventListener("turbo:before-render", this.prepareRender)
    document.addEventListener("turbo:load", this.keepOutOfCache)
    this.resizeObserver = new ResizeObserver(() => this.#reserveSpace())
    this.resizeObserver.observe(this.element)
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this.prepareRender)
    document.removeEventListener("turbo:load", this.keepOutOfCache)
    this.resizeObserver.disconnect()
  }

  toggle({ detail: { eventId, title, eventUrl, saved, media } }) {
    if (this.element.dataset.eventId === String(eventId)) return this.stop()

    this.media = media
    this.switcherTarget.hidden = media.length < 2
    this.titleTarget.textContent = title
    this.#load(0)
    this.#linkTitle(eventUrl)
    this.#showSave(eventId, saved)
    this.element.dataset.eventId = eventId
    this.element.hidden = false
    this.keepOutOfCache()
    this.#announce(eventId)
  }

  previous() {
    this.#load(this.#offset(-1))
  }

  next() {
    this.#load(this.#offset(1))
  }

  stop() {
    this.playerTarget.replaceChildren()
    delete this.playerTarget.dataset.provider
    delete this.element.dataset.eventId
    this.titleTarget.textContent = ""
    this.#linkTitle("")
    this.element.hidden = true
    Turbo.cache.resetCacheControl()
    this.#announce(null)
  }

  // Turbo renders a visit by replacing <body>, and a browser reloads an iframe that is moved,
  // so the music would restart on every visit: while playing, the page is swapped around the
  // dock instead. That keeps the same <body> element, which Turbo clones for its snapshot
  // cache only after the render, so a playing page is exempted from the cache (the setting
  // lives in <head>, which each visit replaces, hence renewing it on turbo:load).
  prepareRender({ detail }) {
    if (!this.#playing) return

    detail.newBody.querySelector(`#${this.element.id}`)?.remove()
    detail.render = (_currentBody, newBody) => this.#swapPageAround(newBody)
  }

  keepOutOfCache() {
    if (this.#playing) Turbo.cache.exemptPageFromCache()
  }

  get #playing() {
    return this.playerTarget.childElementCount > 0
  }

  #swapPageAround(newBody) {
    const body = document.body
    for (const node of [...body.childNodes]) if (node !== this.element) node.remove()
    for (const { name } of [...body.attributes]) body.removeAttribute(name)
    for (const { name, value } of newBody.attributes) body.setAttribute(name, value)
    this.element.before(...newBody.childNodes)
  }

  #load(index) {
    const { provider, src } = this.media[index]
    const frame = document.createElement("iframe")
    frame.src = src
    frame.title = this.titleTarget.textContent
    frame.allow = "autoplay; encrypted-media; fullscreen; picture-in-picture"
    this.playerTarget.replaceChildren(frame)
    this.playerTarget.dataset.provider = provider
    this.index = index
    this.positionTarget.textContent = `${index + 1} / ${this.media.length}`
    this.previousTarget.title = this.media[this.#offset(-1)].via
    this.nextTarget.title = this.media[this.#offset(1)].via
  }

  #offset(step) {
    return (this.index + step + this.media.length) % this.media.length
  }

  #linkTitle(url) {
    if (url) this.titleTarget.href = url
    else this.titleTarget.removeAttribute("href")
  }

  #showSave(eventId, saved) {
    if (!this.hasSaveTarget) return

    this.saveTarget.dataset.saveEventIdValue = eventId
    this.saveTarget.dataset.saveSavedValue = saved
  }

  #announce(eventId) {
    this.dispatch("changed", { target: window, prefix: "media", detail: { eventId } })
  }

  #reserveSpace() {
    const covered = this.element.hidden ? 0 : this.element.offsetHeight + parseFloat(getComputedStyle(this.element).bottom)
    document.documentElement.style.setProperty("--media-dock-clearance", `${covered}px`)
  }
}
