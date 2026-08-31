export async function downscale(file, maxEdge) {
  const bitmap = await createImageBitmap(file)
  const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement("canvas")
  canvas.width = Math.round(bitmap.width * scale)
  canvas.height = Math.round(bitmap.height * scale)
  canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  bitmap.close()

  const encode = (type) => new Promise((resolve) => canvas.toBlob(resolve, type, 0.9))
  const [png, jpeg] = await Promise.all([encode("image/png"), encode("image/jpeg")])
  return png.size <= jpeg.size ? png : jpeg
}

export const isImageType = (type) => type.startsWith("image/")
export const isImage = (file) => isImageType(file.type)
