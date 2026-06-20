# Project instructions — üsgu

## UI changes must conform to the styleguide

There is a living styleguide at `/styleguide` (source: `app/views/styleguide/index.html.erb`). Every specimen renders the **real** shared element/partial with the app's CSS, so it stays truthful.

Before adding or changing a **user-facing UI element**, do this — it applies to genuinely new UI, not routine copy/logic tweaks:

1. **Look first.** Check `/styleguide` and `app/views/shared/` for an existing component, partial, or CSS class that already covers the pattern (back link / page header, buttons, chips, fields, icons, …). Reuse it — don't hand-roll a one-off.
2. **If nothing fits, make it shared.** Add the new element as a shared partial/class and document it with a specimen in the styleguide, then use that. Don't introduce a bespoke variant that silently diverges from a sibling page.
3. **Don't ship competing cross-file selectors.** CSS is global (propshaft bundles all of `app/assets/stylesheets`, cascade = alphabetical filename). One pattern → one home.

The page header is the worked example: `shared/_page_header` (+ `shared/_back_link`) is the single source for the back link + title block. Use `render layout: "shared/page_header"` rather than writing a fresh `<header>` / back link.
