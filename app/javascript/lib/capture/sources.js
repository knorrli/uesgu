export class CaptureSources {
  constructor() {
    this.byRow = new Map()
    this.inputByRow = new Map()
    this.spentByInput = new Map()
  }

  remember(rowId, inputId, source) {
    this.byRow.set(rowId, source)
    this.inputByRow.set(rowId, inputId)
  }

  get(rowId) {
    return this.byRow.get(rowId)
  }

  has(rowId) {
    return this.byRow.has(rowId)
  }

  inputFor(rowId) {
    return this.inputByRow.get(rowId)
  }

  spent(rowId) {
    return this.spentByInput.get(this.inputFor(rowId)) ?? 0
  }

  spend(rowId) {
    const next = this.spent(rowId) + 1
    this.spentByInput.set(this.inputFor(rowId), next)
    return next
  }

  clear() {
    this.byRow.forEach(({ objectUrl }) => { if (objectUrl) URL.revokeObjectURL(objectUrl) })
    this.byRow.clear()
    this.inputByRow.clear()
    this.spentByInput.clear()
  }
}

export function posterImage(objectUrl, alt) {
  const image = document.createElement("img")
  image.src = objectUrl
  image.alt = alt
  return image
}
