// The template of a <turbo-stream> is inert markup, so what it carries has to be
// reached through it rather than by querying the parsed document.
export function streamedContent(stream) {
  const template = new DOMParser().parseFromString(stream, "text/html").querySelector("turbo-stream template")
  return template?.content ?? null
}
