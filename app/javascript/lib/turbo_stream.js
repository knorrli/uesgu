export function streamedContent(stream) {
  const template = new DOMParser().parseFromString(stream, "text/html").querySelector("turbo-stream template")
  return template?.content ?? null
}
