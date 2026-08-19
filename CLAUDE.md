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
  issues** — they never close. Those belong in design docs under `docs/` (or the
  assistant memory). Don't reopen a settled decision as an issue.

There is a living styleguide at `/styleguide` (source: `app/views/styleguide/index.html.erb`). Every specimen renders the **real** shared element/partial with the app's CSS, so it stays truthful.

Before adding or changing a **user-facing UI element**, do this — it applies to genuinely new UI, not routine copy/logic tweaks:

1. **Look first.** Check `/styleguide` and `app/views/shared/` for an existing component, partial, or CSS class that already covers the pattern (back link / page header, buttons, chips, fields, icons, …). Reuse it — don't hand-roll a one-off.
2. **If nothing fits, make it shared.** Add the new element as a shared partial/class and document it with a specimen in the styleguide, then use that. Don't introduce a bespoke variant that silently diverges from a sibling page.
3. **Don't ship competing cross-file selectors.** CSS is global (propshaft bundles all of `app/assets/stylesheets`, cascade = alphabetical filename). One pattern → one home.

The page header is the worked example: `shared/_page_header` (+ `shared/_back_link`) is the single source for the back link + title block. Use `render layout: "shared/page_header"` rather than writing a fresh `<header>` / back link.

## Comments

**This repeats the global rule in `~/.claude/CLAUDE.md` because it keeps getting
missed — it was raised on four consecutive PRs. Run the check below before opening
one; a comment that fails it is a review finding, not a style preference.**

Code must be self-documenting: *what* it does has to be clear from reading it.
Reach for a better name, a smaller method, or a clearer structure before reaching
for a comment.

Only write a comment carrying something that **cannot** be recovered by reading the
code:

- a constraint or gotcha imposed from outside — a library's surprising behaviour,
  an API contract, a browser/renderer quirk, a spec clause
- a special case and why it exists — the bug it prevents, the input that breaks
  without it
- why a non-obvious approach was chosen where the obvious one looks correct
- a warning that changing this breaks something non-local

Never write a comment that restates the code, narrates control flow, labels a
block, announces what the next line does, or repeats intent already stated by the
method or test name.

Prefer one dense comment at the top of a construct over running commentary inside
it, and never explain the same thing at two altitudes — a class header that
re-explains what a method's own comment already says is duplication that will drift.

**The check, before every PR:** re-read each comment you added and name which
bullet above it satisfies. If you cannot, delete it. Watch for these, which are
what actually slips through here:

- A comment whose first sentence paraphrases the method body (`# Registry first,
  then an existing place, then a new one` above code that reads exactly that).
- A test comment restating its own `test "..."` name.
- Rationale copied into a second file instead of pointed at (`see
  EventCapture::Extractor`), so the two copies can disagree later.
- Density: comments are dense here by house style, but a hunk that is ~40%+ comment
  is a prompt to cut, not a target to hit.

Design rationale belongs in `docs/`, not duplicated in prose above the code that
implements it. Link to the doc instead.
