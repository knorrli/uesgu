# Design language — üsgu

**Date:** 2026-06-16 · **Branch:** `ui-design-pass`
**Status:** agreed rules for the systemic design pass (pass-2).

This is the **prescriptive** companion to the descriptive [`ui-audit.md`](ui-audit.md).
The audit catalogues what exists; this file states the rules we enforce and the
deltas from today's code. The living `/styleguide` should be rebuilt to embody
these rules *in context* (not as isolated swatches) so the app can't drift back.

Pass-1 changed *values* (contrast token, borders, calendar width). This pass
changes the *system*: a few invariants, enforced everywhere, even where a piece
was already individually "spec-compliant." Guardrail: **don't sand off identity**
— the punched-out plum-text-on-green button is character, keep it.

## The three invariants

1. **What is clickable is unambiguous.** A clickable thing looks clickable; static
   text and separators never borrow an interactive treatment.
2. **Every element has ONE visual representation.** One role → one look,
   app-wide. The button ladder below is the vocabulary; nothing reinvents it.
3. **One job per color.** Each semantic color means exactly one thing.

## Color semantics — green dominates, raspberry is rare

Green is the **dominant accent** — it should be present across the page and
contrast the pink/plum ground. Raspberry is **rare highlighted spots**, reserved
for the single most precious signal. So each "yours" signal maps to the colour
whose *frequency* matches: follows are frequent → green (keeps green omnipresent);
saves are rare → raspberry (the highlight). (Revised 2026-06-16 after seeing
follows-in-raspberry: raspberry dominated and green vanished — the inverse of what
we want.)

| Color | Token | Means | Applied to |
|---|---|---|---|
| **Green** | `--theme-accent-color` | **interaction / state / follows** — the dominant accent | links, focus, "today", selected/active, **followed venues + styles**, follow star + calendar dot |
| **Raspberry** | `--theme-favorite-color` | **saved** — the rare highlight | saved-show heart (per-event button + calendar marker) |
| **Warn** | `--theme-warn-color` | **destructive** | delete / dangerous commit |
| **Neutral** | fg-derived tints | **structure only** | borders (`--border-color`), content rules (`--rule-color`), grid |
| **On-accent** | `--theme-on-accent` | content sitting on green | button text, ticks, badges |

Green carries several jobs (interaction, state, follows) but stays unambiguous
because each gets a distinct *treatment*: a link is underlined / has the ↗ arrow,
a follow carries the **star** glyph, "today" is a filled box. Green is the layer
of "alive / active / yours"; neutral is static structure; raspberry is your rare
saved gems.

## Palette (decided 2026-06-16, may still be value-tuned)

Light theme = **dirty-cream ground + mid-deep green**, dark theme unchanged.
On-accent text **matches the background** ("punched out"), legible in both because
each theme pairs a light-ish on-accent with a dark-enough green fill.

| Token (light) | Value | Note |
|---|---|---|
| `--color-background` | `#e8e1cd` | muted warm sand, not bright white (easy on eyes) |
| `--color-accent` | `#0e7a4a` | reads as green for links/text on cream; dark enough for cream-on-green button punch-out |
| `--theme-on-accent` | `var(--color-background)` | cream text punched out of the green fill |
| `--theme-bg-muted` | bg − 10% L | the sand highlight — shared by the dropdown option AND the calendar day hover/selected (one interaction language) |

Rejected en route: pink + deep-emerald (deep green muddies to grey as link *text*
on pink — only works as a fill); white-on-bright-green (no punch-out character).
Dark theme already nails the punched-out look natively. Exact hexes still open.

## Icon language

Two personal signals, deliberately weighted differently:

Distinct in **both colour and shape** so the two signals never blur together:

| Signal | Frequency | Glyph | Color |
|---|---|---|---|
| **Saved show** (Merkliste) | rare, powerful | **♥ heart** | **raspberry** (the rare highlight) |
| **Interested / followed** (Interessen) | frequent | **★ star** (default; pin/plus are easy swaps) | **green** (the dominant accent) |

**Delta from today:** the heart migrated *interested → saved*; interested took the
**green star**. The bookmark glyph is retired. Pairing each signal's colour to its
frequency (frequent=green, rare=raspberry) is what keeps green dominant and
raspberry rare.

One disclosure glyph everywhere: the Phosphor **caret** (`--caret-mask`) — never a
mix of caret here and a different icon there for the same "expand/dropdown" action.

## Button ladder (already canonical in `controls.css` — enforce, don't reinvent)

| Role | Class / markup | Look |
|---|---|---|
| NEUTRAL | `button` / `.button` | muted boxed button |
| PRIMARY | `input[type=submit]` | filled green (commit a form) |
| SECONDARY | `.button-small` | filled green pill |
| TERTIARY | `.button-small.button-ghost` | hollow green pill |
| DANGER | `.button.delete` / `.button-small.danger` | hollow warn → fills warn on commit |
| ICON | `.icon-button` (+`.danger`) | flat boxless inline icon action |
| LINK | `.text-link` | underlined green navigation |

"A box reads as clickable" — every button is a box; only `.text-link` is borderless.
The "3 button styles / 4 link styles" complaints are places **not using** this
ladder → an enforcement sweep, not a new design.

## Affordance & structure rules

- **Booleans:** one custom box (`input[type=checkbox]` in `controls.css`), one
  tick. No native checkbox/toggle sneaks in beside it; selectable chips/options
  share this language (border + on-accent tick), never color-only state.
- **Separators:** exactly two weights — a hairline `--border-color` (incidental
  division) and a `--rule-color` content rule (date headings, drawer frames).
  No third ad-hoc separator; fieldset borders use the same tokens.
- **Destructive is always warn**, at every size (`.delete` / `.danger`) — never a
  green "löschen."

## Enforcement deltas (what actually changes in code)

1. ✅ (events slice) Interested/follow = **green star**: `.event-tag.fav.followed`,
   `.fav-heart` (→star, green fill), `.date-favorite-marker`, `.day-favorite-marker`
   (green dot), `.favorites-filter-link.active`. Saved = **raspberry heart**:
   `.save-bookmark` (→heart), `.day-saved-marker` (→heart). Bookmark glyph retired
   (`--bookmark-*` vars now unused). New `--star-*` masks in `variables.css`.
   Propagate to the rest of the app (saved-shows page, favorites, notifications).
2. ⏳ Audit every `löschen`/delete path → `.delete`/`.danger` (kill any green delete).
3. ⏳ Sweep button/link instances onto the ladder; remove bespoke variants.
4. ⏳ Normalize separators to the two-weight rule; same caret for all disclosure.
5. ⏳ Rebuild `/styleguide` to show these rules in context (its `.fav-heart` /
   `.save-bookmark` labels are now stale — heart=saved, star=interested).
6. ⏳ Cleanup (non-visual): rename `.fav-heart`→`.fav-star`, `.save-bookmark`→
   `.save-heart`, `--theme-favorite-color`→`--theme-saved-color`; drop `--bookmark-*`.

Verify each by before/after screenshots (the cold-eyes method in
`project-screenshot-design-review`), not by checklist.
