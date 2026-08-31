export function searchForSuggestion(raw, template, blankLabel) {
  const value = (raw || "").trim()
  if (value === "") return { value: "", label: blankLabel, blank: true }

  return { value, label: template.replaceAll("%{query}", value), blank: false }
}
