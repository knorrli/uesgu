// Shared "search for «X»" free-text logic for the event filter — the one piece
// of behaviour the desktop combobox (tag_picker_controller) and the mobile sheets
// (filter_sheets_controller) must agree on. Both fields accept a free-text query
// alongside the fixed style options; this decides when to offer it.
//
// Given the raw typed text and the labels already offered as options, returns
// { show: false } when the text is blank or exactly matches an existing option,
// otherwise { show: true, value, label } — `value` is the query to submit and
// `label` is the localized "Search for «X»" string (template's %{query} filled).
//
// Keeping this in one place is what lets the two UIs stay aligned instead of
// drifting (the desktop affordance was missing precisely because this lived only
// in the mobile controller).
export function searchForSuggestion(raw, existingLabels, template) {
  const value = (raw || "").trim()
  if (value === "") return { show: false }

  const needle = value.toLowerCase()
  const exactMatch = existingLabels.some((label) => label.trim().toLowerCase() === needle)
  if (exactMatch) return { show: false }

  return { show: true, value, label: template.replaceAll("%{query}", value) }
}
