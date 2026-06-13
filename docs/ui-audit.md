# UI Audit — üsgu

**Date:** 2026-06-13
**Scope:** Every reusable UI element across the app, both the desktop/browser layout and the mobile (`< 600px`) layout. This is Phase 1 of the UI-unification effort: *extract and classify what exists today and flag where elements drift from a single, telegraphed purpose.* It is descriptive, not prescriptive — the intended look/purpose decisions live in the living styleguide (`/styleguide`).

## How the design system is wired

The whole UI is plain CSS (no utility framework), mobile-first, with a small token layer:

- **`variables.css`** — raw palette (`--color-green #0e8857`, `--color-pink`, `--color-red`, `--color-amber`, `--color-raspberry`, …), spacing scale (`--gap-xsmall…xlarge`), type scale, `--border-radius: none` (the app is intentionally square-cornered), and the heart/check SVG masks.
- **`theme.css`** — maps palette → semantic tokens on `body`: `--theme-accent-color` (green), `--theme-warn-color` (red), `--theme-favorite-color` (raspberry), `--theme-bg-color` (pink), plus computed `--theme-fg-muted`, `--theme-bg-muted`, `--theme-accent-muted`. A single `html[data-theme="dark"]` block re-points the palette for dark mode. Theme is resolved pre-paint in the layout `<head>` and cycled by `theme_controller.js` (system → light → dark).
- All stylesheets are bundled via `stylesheet_link_tag :app` in `layouts/application.html.erb:49`, so **any page automatically gets every component style** — this is what makes a living styleguide possible.

### Semantic colour intent (as designed)

| Token | Colour | Intended meaning |
|---|---|---|
| `--theme-accent-color` | green | Interactive / primary action / link / **active** state |
| `--theme-favorite-color` | raspberry | "Yours" — a **followed** item (favorites) |
| `--theme-warn-color` | red | Destructive / error |
| `--color-amber` | amber | Neutral "empty / nothing here" status |
| `--theme-fg-muted` | grey | Secondary text, at-rest icon/chrome |

The core tension this audit surfaces: **green is asked to mean too many things** (see Inconsistency #1).

---

## 1. Buttons & actions

| Variant | Class / markup | Defined | Used (sample) | Look | Role |
|---|---|---|---|---|---|
| Primary submit | `input[type=submit]` | `controls.css:48` | settings:36/53, registrations:22, sessions:7, rules/new:123 | Filled accent (green) bg, bg-coloured text | Commit a form |
| Boxed button base | `button`, `a.button` | `controls.css:1` | (base) | Muted-grey filled box, accent border | Generic clickable box |
| Flattened button | `.button` reset | `application.css:44` | view-switcher, favorites shortcut | **Stripped back to bare** (no box/border) | Inline text action |
| Delete (account) | `.button.delete` | `application.css:52` + `controls.css:12` | settings:108 | Full-width, **warn (red) border**, no fill | Destructive, heavyweight |
| Pill action | `.button-small` | `notification_rules.css:53` | rules/index:33, scrape_runs | Small filled-accent pill | Secondary commit ("Fire now", "Trigger") |
| Ghost pill | `.button-small.button-ghost` | `notification_rules.css:63` | rules/index:34/36, rules/new:124 | Hollow accent pill | Tertiary ("Edit filter", "Enable/Disable", "Cancel") |
| Danger pill | `.button-small.danger` | `notification_rules.css:68` | rules/index:38 | Hollow **warn** pill | Destructive (delete rule) |
| Icon button | `a.icon-button` / `button.icon-button` | `controls.css:30` | _event:26/37, genre gears | Flat, boxless, **muted** glyph, fg on hover | Inline icon action |
| Icon button (danger) | `.icon-button.danger` | `controls.css:44` | _event:40 | Same + warn on hover | Inline destructive icon |
| Sheet apply | `.sheet__apply` | `events.css` | _filter_sheets:115/173/213 | Full-width filled accent | Commit a mobile filter sheet |
| Notify link | `.button.notify-filter-link` | `notification_rules.css:123` | _notify_button:9 | Flat accent text + leading bell | "Notify me about this" |
| Theme toggle | `.theme-toggle` | `layout.css:55` | layout:67 | Icon-only, accent glyph | Cycle theme |

**Observations**
- There are **three parallel button vocabularies**: `input[type=submit]` (primary, filled), `.button-small[.button-ghost|.danger]` (the rules-screen pill family), and `.button` (reset to bare text). They were grown per-screen, not from one ladder.
- The *same semantic action* — destructive — is expressed two unrelated ways: `.button.delete` (full-width red-bordered) vs `.button-small.danger` (small hollow red pill). See #2.
- `.button` is defined as a *boxed* button in `controls.css:1` and then *un-styled back to bare* in `application.css:44`, with per-screen CSS re-styling it again (view-switcher). Fragile cascade; the class name no longer telegraphs anything.

## 2. Pills / badges / chips

| Variant | Class | Defined | Interactive? | Look | Role |
|---|---|---|---|---|---|
| Info chip | `.chip` | `notification_rules.css:37` | No | Muted hairline, muted text | Read-only metadata ("In-app", "Push") |
| Window chip | `.chip--window` | `notification_rules.css:137` | No | Accent border + `accent-muted` fill | Date/window or "favorites live" |
| Type chip | `.chip--type` | `notification_rules.css:142` | No | Quiet grey fill, no border | Rule type ("New" / "What's on") |
| Muted chip | `.chip--muted` | `notification_rules.css:46` | No | Greyed | "Disabled" |
| Count badge | `.badge` | `layout.css:125` | No | Filled accent, bg text | Unread count, "+N more" |
| Filter-trigger badge | `.filter-trigger__badge` | `events.css` | No | Filled accent | Count on mobile filter trigger — **duplicate of `.badge`** |
| Selection tag | `.tag` / `.tag.active` | `tags.css:1` | Yes/No | Hairline; **filled accent when active** | A style/query token; active = selected |
| Delete tag | `button.tag` | `tags.css:19` | Yes | Muted-grey fill | Suggested style, click to apply/remove |
| Label tag | `label.tag` (`:has(:checked)`) | `tags.css:33` | Yes | Fills accent when checked | Favorite-styles picker |
| Status badge | `.scrape-badge--ok/empty/failed/running` | `admin.css:174` | No | **Solid** green / amber / red / grey | Scrape outcome |
| Applied filter chip | `.filter-chip` (`__icon/__label/__remove`) | `events.css:663` | Yes (tap removes) | Filled accent + trailing `ph-x` | Active filter, removable |

**Observations**
- **`.chip`, `.tag`, `.badge`, `.filter-chip`, `.scrape-badge` are five separate pill families** with overlapping visuals. `.chip` (read-only) and `.tag` (clickable) look similar but mean opposite things w.r.t. interactivity; `.tag.active` and `.filter-chip` both come out filled-accent yet one lives in a form and one doesn't (see #5).
- `.badge` and `.filter-trigger__badge` are byte-for-byte the same intent (a small accent count pill) defined twice — drift risk (#11).
- The status badges are the **one place solid colour fills carry meaning by hue** (green=ok / amber=empty / red=failed). That's a distinct, legitimate system — but it means a *solid green pill* means "success" in admin while *solid green* elsewhere means "primary action / selected". Worth calling out so the styleguide keeps them clearly separated.

## 3. Dropdowns / selects / combobox

| Variant | Class / markup | Defined | Icon? | Notes |
|---|---|---|---|---|
| Styled native select | `.account-form select` | `application.css:80` | **Custom SVG chevron** (hard-coded green) | Underline field; chevron colour is a literal `%230e8857` in the SVG data-URI — won't follow dark theme (#1/#10) |
| Multiselect combobox | `f.combobox(... multiselect_chip_src:)` | `_hotwire_combobox_overrides.css` | search glyph | Filter What/Where; renders chips |
| Sheet search | `.sheet__search-input` + `.sheet__search-icon` | `events.css` | `ph-magnifying-glass` | Mobile sheet search |
| Account menu | `<details>.nav-menu` | `layout.css:74` | **`▾`/`▴` unicode**, not a Phosphor icon | Everywhere else uses Phosphor; this uses a text glyph (#3/icon consistency) |

**Observations**
- Dropdown indicators are inconsistent in *kind*: the account menu uses a Unicode `▾`, the select uses a hand-inlined SVG with a **hard-coded green hex** (breaks theming + duplicates the accent value), and the rest of the app uses the Phosphor icon font. A single charet treatment (Phosphor `ph-caret-down`, `currentColor`) would unify them.

## 4. Form inputs

| Variant | Class | Defined | Look |
|---|---|---|---|
| Account/auth fields | `.account-form input[type=text/email/password]`, `select` | `application.css:59` | **Underline only**, accent bottom-border, accent on focus→fg |
| Filter text input | `input[type=text]` (in `.filter`) | `controls.css:69` | Borderless, grows in flex, ellipsis |
| Custom date range | `.custom-range__input` | `events.css` | Native date, underline |
| Native checkbox/radio | `input[type=checkbox/radio]` | `controls.css:64` | Native, `accent-color` green |
| Custom checkbox (sheets) | `.opt input[type=checkbox]` → `.opt__box` | `events.css` | Hidden native; custom drawn box + masked check |
| Favorite-styles checkbox | `label.tag input` | `tags.css:37` | Hidden; chip fills accent when checked |
| Global input colour | `input { color: accent }` | `theme.css:53` | **All typed text is green** |

**Observations**
- `theme.css:53` sets *all* `input` text to the accent green. Combined with green underlines, form fields read very green — reinforcing the "green everywhere" dilution (#1).
- **Checkbox has three implementations**: native (settings/rules forms), custom `.opt__box` (mobile filter sheets), and chip-fill (`label.tag`). The first two can both be seen by one logged-in user (notification settings + mobile filters), creating a visual seam (#4).
- Two input "skins" — underline (`.account-form`) vs borderless-grow (`.filter`) — are each internally consistent and arguably justified (form vs filter bar), but should be named/documented as two deliberate field types, not left implicit.

## 5. Icons (Phosphor)

Base class `ph`, hearts are masked SVGs (see memory: Phosphor Regular, `ph` base). Icons in active use, via `tags_helper`/`events_helper` and templates: `ph-circle-half-tilt` (theme), `ph-gear` (edit), `ph-trash` (delete), `ph-bell` (notify), `ph-x` (close/remove), `ph-magnifying-glass` (search), `ph-caret-right/down` (disclosure), `ph-map-pin`/`ph-house`/`ph-map-trifold` (location: city/venue/canton), `ph-music-notes`/`ph-tag` (style/genre), `ph-calendar-dots` (date), `ph-arrow-right` (range separator), `ph-bookmark-simple` (save), `ph-lightning` (fallback).

**Observations**
- **Icon styling forks**: clickable icons should use `.icon-button` (muted→fg on hover, `.danger` variant), but several inline icons are styled ad-hoc by their context (`.sheet__search-icon`, `.sheet__close` combines `ph ph-x` directly on a button, `.meta-edit` adds its own margin). There's no shared **display-only icon** role distinct from the clickable `.icon-button` role.
- Two non-Phosphor disclosure glyphs exist (`▾` in the nav menu; the inline-SVG chevron in the select) where Phosphor carets would unify (#3).
- `.filter-icon` (the leading handle icon in filter fields) is coloured `var(--border-color)` = **green** (`events.css:10`). A green field-label icon competes with the "green = interactive" signal (#10).

## 6. Colour usage — where green drifts off-purpose

Green (`--theme-accent-color`) is intended to mean *interactive / primary / active / followed-ish*. It is currently **also** used as:

- `--border-color: var(--theme-accent-color)` (`theme.css:11`) → the default border colour app-wide: **site header/footer rules** (`layout.css:4/116`), the **nav-menu panel border**, **calendar grid lines**, section dividers.
- **All `.account-form` input underlines** (`application.css:65`) and the **global `input { color: accent }`** (`theme.css:53`) — passive form chrome rendered as if it were a call to action.
- The **leading filter handle icons** (`.filter-icon`, `events.css:10`).
- A **hard-coded `#0e8857`** baked into the select-chevron SVG data-URI (`application.css:85`) — a literal duplicate of the token that also won't recolour in dark mode.

Other colours are well-behaved: raspberry is used *only* for followed/favorite markers (`.fav-heart` filled, `.date-favorite-marker`, active favorites filter); red only for destructive/error; amber only for the empty scrape status. The cleanup opportunity is almost entirely about **separating "structural border / passive chrome" from "interactive accent"** so green regains a single meaning.

## 7. Navigation / layout

- **Header** (`.site-header`): brand (home link) + icon-only theme toggle, accent bottom border. `layout.css:3`.
- **Nav** (`.site-nav`): logged-out = inline Login/Signup links; logged-in = a single `<details>.nav-menu` dropdown (Notifications +`.badge`, Rules, Saved, Favorites, Settings, Admin, Logout) with an `.unread-dot` on the trigger. `layout.css:37`.
- **Footer** (`.site-footer`): muted tagline only, accent top border. `layout.css:114`.
- **View switcher** (`.view-switcher`): flat List/Calendar text toggle, active=bold accent. `events.css:316`.
- **Filter — two parallel UIs**:
  - **Inline** (`.filter`, `_filter.html.erb`) ≥600px: horizontal combobox fields (What/Where/When) with leading icon + applied `.tag` chips.
  - **Mobile sheets** (`.filter-sheets`, `_filter_sheets.html.erb`) <600px: trigger bar (3 buttons + count badges) and full-screen What/Where/When sheets with `.opt` rows, search, location tree (`.loc-group`), and a `.sheet__apply`. (See memory: mobile filter sheets DONE & live.)
- **Calendar** (`.simple-calendar`): day cells, today badge (filled accent), selected-day frame, busyness bar. `events.css:379`.
- **Admin lists/catalogues** (`.admin-list`/`.admin-row`/`.heading-link`/`.stat-link`): dotted-leader rows, hover reveal arrow. `admin.css`.

---

## Candidate inconsistencies (ranked)

1. **Green does too many jobs.** It is the interactive/primary/active/followed signal *and* the default structural border (`--border-color`), all passive input chrome, grid lines, and field-label icons. This is the single biggest dilution. → Introduce a neutral `--border-color` (and `--field-rule` for passive underlines) distinct from `--theme-accent-color`; reserve green for links, active states, primary buttons.
2. **Destructive actions have two unrelated looks.** `.button.delete` (full-width red-bordered) vs `.button-small.danger` (small hollow red pill). → One `danger` role that scales by size, not two classes.
3. **Disclosure indicators use three different glyph systems.** Phosphor carets (filters), Unicode `▾` (nav menu), hand-inlined SVG with hard-coded hex (select). → Standardise on Phosphor `ph-caret-down` + `currentColor`.
4. **Three checkbox implementations** (native / `.opt__box` / chip-fill), two of which a single user meets. → Pick one custom box and reuse, or scope the difference deliberately (form vs sheet) and document it.
5. **`.tag.active` vs `.filter-chip`** look identical (filled accent) but one is a form button and one a JS-removed chip; neither clearly reads "removable". → Distinguish selected-token vs removable-applied-filter, give removable chips an explicit affordance.
6. **`.button` is defined, then un-defined, then re-defined per screen.** The class telegraphs nothing. → Rename to domain classes (`.view-switch__item`, etc.) and reserve `.button` for an actual button look — or drop it.
7. **Three button vocabularies** (`input[type=submit]`, `.button-small*`, `.button`) grown per-screen. → One primary/secondary/tertiary/danger ladder, applied to both `<input>`, `<button>`, and `<a>`.
8. **`.badge` and `.filter-trigger__badge` are duplicate definitions** of the same count pill. → Share one `.badge`/`.count-badge`.
9. **`.icon-button` (clickable) has no display-only counterpart.** Inline non-clickable icons get ad-hoc colours (`.filter-icon` green, `.sheet__search-icon`, `.meta-edit`). → Add an `.icon` (display) role beside `.icon-button` (action); colour display icons muted.
10. **`.filter-icon` is green** (`--border-color`), competing with the interactive signal. → muted.
11. **Hard-coded `#0e8857`** in the select-chevron SVG (`application.css:85`) duplicates the accent token and ignores dark theme. → Re-derive from `currentColor`/token, or use a Phosphor caret.
12. **Missing interaction states.** No shared `:focus-visible` ring; `:disabled` only on `input[type=submit]`; no loading state for async buttons ("Fire now"); `.filter-chip` has no `:hover`. → Add baseline focus/disabled across interactive roles.

### Not bugs — deliberate, keep
- Square corners (`--border-radius: none`), hairline separators over cards, mobile-first.
- Raspberry strictly = followed/yours; red strictly = destructive/error; amber = empty status. These three are clean.
- Inline filter (desktop) vs full-screen sheets (mobile) is an intentional responsive split, not duplication to merge.

---

*Next: the living styleguide at `/styleguide` renders each element above with the real CSS and states a single intended purpose per element. Phase 4 (applying the unified styles) is held for review.*
