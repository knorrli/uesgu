// Shared "search for «X»" free-text logic for the event filter — the one piece
// of behaviour the desktop combobox (tag_picker_controller) and the mobile sheets
// (filter_sheets_controller) must agree on. Both fields accept a free-text query
// alongside the fixed style options; this decides what the affordance row reads.
//
// The row is ALWAYS shown (a constant cue that typing searches everything, not
// just the dropdown — the placeholder alone didn't convey it). Given the raw
// typed text it returns { value, label, blank }:
//   - blank input → { value: "", label: <blankLabel>, blank: true }  (a hint;
//     value is empty so callers' commit guards make it a no-op)
//   - typed text  → { value, label: "<verb> «query»", blank: false } (committable)
//
// Keeping this in one place is what lets the two UIs stay aligned instead of
// drifting.
export function searchForSuggestion(raw, template, blankLabel) {
  const value = (raw || "").trim()
  if (value === "") return { value: "", label: blankLabel, blank: true }

  return { value, label: template.replaceAll("%{query}", value), blank: false }
}
