# Project instructions — üsgu

## Branches & PRs

`main` is protected — land everything via PR (CI must be green). Branch names are
load-bearing: the prefix drives the release-notes category via
`.github/workflows/label-pr.yml`.

- **Prefix every branch** `feat/…`, `fix/…`, or `chore/…`, chosen from the
  change's primary intent *before* creating it. `feat/`→ Features, `fix/`→ Fixes,
  anything else → Maintenance.
- **One branch = one coherent change.** Never pile unrelated work onto an
  existing branch. If scope drifts (a `fix/` sprouts a feature, or a branch turns
  into a grab-bag), split it — or at minimum re-label the PR so the auto-generated
  release notes stay honest.
- Keep PRs small and reviewable. Releases are cut with `bin/release X.Y.Z`, which
  refuses to tag unless CI is green on the commit.

## Tracking open work

Open work lives in **GitHub issues**, not in the repo (there is no `BACKLOG.md`).
With `main` PR-gated, an in-repo backlog meant a PR + CI round-trip for every note;
issues sidestep that and self-close from PRs (`Closes #N`). Conventions:

- **Anything that could become actionable → an issue.** Use `feature` / `chore` /
  `bug` / `documentation`; tag not-yet-active ideas `maybe-later`.
- **Durable decisions and "we rejected X because Y" rationale do _not_ go in
  issues** — they never close. There is no `docs/` directory: that rationale goes in
  the PR description (reviewed once, then archived) and, when it must survive, in the
  assistant memory. Don't reopen a settled decision as an issue, and don't start a
  design doc for it.

There is a living styleguide at `/styleguide` (source: `app/views/styleguide/index.html.erb`). Every specimen renders the **real** shared element/partial with the app's CSS, so it stays truthful.

Before adding or changing a **user-facing UI element**, do this — it applies to genuinely new UI, not routine copy/logic tweaks:

1. **Look first.** Check `/styleguide` and `app/views/shared/` for an existing component, partial, or CSS class that already covers the pattern (back link / page header, buttons, chips, fields, icons, …). Reuse it — don't hand-roll a one-off.
2. **If nothing fits, make it shared.** Add the new element as a shared partial/class and document it with a specimen in the styleguide, then use that. Don't introduce a bespoke variant that silently diverges from a sibling page.
3. **Don't ship competing cross-file selectors.** CSS is global (propshaft bundles all of `app/assets/stylesheets`, cascade = alphabetical filename). One pattern → one home.

The page header is the worked example: `shared/_page_header` (+ `shared/_back_link`) is the single source for the back link + title block. Use `render layout: "shared/page_header"` rather than writing a fresh `<header>` / back link.

## Comments

**This repo has no comments.** That is not shorthand for "few" — outside the
exceptions listed below, `app/`, `lib/`, `test/`, `config/`, `script/` and the
stylesheets contain zero. Match what you see: if a file you are editing has no
comments, the change you add to it has none either.

Code must be self-documenting. Reach for a better name, a smaller method, or a
clearer structure — those are the only tools. Design rationale goes in the PR
description.

The exceptions, all of which already exist and none of which you should extend
without saying so in the PR:

- `app/assets/stylesheets/_hotwire_combobox_overrides.css` — every rule works
  around a value the gem hardcodes, so every rule is annotated.
- `app/javascript/controllers/install_controller.js` — what each browser engine
  supports, which is the only reason the branching exists.
- A handful of single blocks pinning an external fact the code cannot state: the
  Rails inflector turning `saves` into `safe`, `NOT IN (NULL)` being SQL-unknown,
  a unique index comparing `''` but not `NULL`, `Time.zone.parse` returning today
  for a bare date, webrobots fabricating `Disallow: /` on an unreachable
  robots.txt, Turbo painting a stream action on the next animation frame,
  Firefox ignoring `line-height` on a single-line `<input>`, iOS Safari putting
  an `<input list>` datalist somewhere the suggestions never show.

The test for a new one: name the third party — a library, a browser, a spec, the
database — whose behaviour forces the code to look wrong. If the sentence is
about *our* design instead, it belongs in the PR.
