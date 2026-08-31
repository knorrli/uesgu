// Shrinking happens on the client because there is no image library in the bundle and
// none on the deployed box — and the canvas re-encode drops EXIF, so a poster photo's
// GPS never leaves the device, which a server-side resize could never achieve.
//
// Encoded BOTH ways because canvas PNG output is unoptimised: on a real poster sample
// it came out at 1.81MB against 221KB as JPEG, 32% larger than the 1.37MB source.
// Flat-colour screenshots, where PNG genuinely wins, still get PNG.
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
