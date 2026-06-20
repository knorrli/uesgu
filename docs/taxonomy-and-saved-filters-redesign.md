# Redesign: one genre tree + saved filters (drop Style + Interests)

Status: **design agreed, not yet implemented.** Captures the model we settled on in
discussion so the thread isn't the source of truth.

## Why

Two parallel systems exist today that turn out to be one thing:

- **Styles** — a hand-curated second taxonomy layer (~15 buckets) rolled up from
  ~292 scraped **genres** via a `Style↔Genre` HABTM, materialised as `styles`
  taggings on every event. Its jobs: the followable object, the music/non-music
  gate, and the curated browse vocabulary.
- **Interests** (favorites) — `User#style_list`/`location_list`, exact-matched, used
  for the "My interests" scope and calendar markers.
- **Notification rules** — *a saved landing-page filter + a schedule*
  (`NotificationRule` freezes a `Filter` and matches with `Filter#ransack_query`).

A notification rule is already a saved filter that accepts any mix of
genre/freetext/location/date. Interests are just "a saved filter you apply." And
styles are just genres that sit high in a hierarchy. So we collapse all three into:

- **one taxonomy**: a self-referential **genre tree**, and
- **one user concept**: a **saved filter** (notification delivery optional).

## Locked decisions (from discussion)

1. **Tree, not DAG.** A genre has one `parent_id`. Multi-home genres pick a primary
   parent or get promoted to a root. DAG remains a clean future upgrade (keep
   `parent_id` as "primary", add an edges table) if ever needed.
2. **Interests is not a feature.** It dissolves into saved filters. "My interests" /
   calendar markers become a *derivation*: the OR-union over the user's saved filters.
   `User#style_list`/`location_list`, the favorites page, and `track_favorites` are removed.
3. **The main page filter is always ephemeral.** It is URL state (`q/s/l/d`), never
   bound to a saved object. "Saved?" is *derived* by matching the live filter's
   fingerprint against the saved set — no stored "active filter" pointer (that pointer
   is what went stale last time).
4. **Three explicit, mode-free operations:** **Apply** (copy a saved filter into the
   URL; the link is then severed), **Save** (snapshot the current URL filter, deduped
   by fingerprint), **Manage** (delete / toggle notify / edit-in-a-dedicated-editor).
   No in-place editing of a saved filter from the main page.
5. **Row shows the event's own genres only.** Subgenres highlight under an ancestor
   filter via descendant-set membership (no name-matching), reusing the set the filter
   already computes.
6. **Browse ranking starts simple** (parent/root genres, alphabetical within a level).
   Leave a hook for a later `featured`/`main_genre` flag and/or subtree-count ordering.
7. **Drop & recreate, no live-data migration.** No real users yet. Build for a quick
   reset; the real artifact is a **seed** (a curated genre tree). The current flat
   genre list does not carry over.
8. **Deferred:** the "Update the filter I just applied" affordance (a session-only soft
   pointer offering "Update 'X'?" beside "Save as new"). Ship without it; add only if
   the refine-over-time need turns out to be real.

## The model

### Genre tree
- `genres.parent_id` (self-ref, nullable). `Metal` is a genre with children
  `Black Metal`, `Speed Metal`; depth is arbitrary (`Rock > Punk > Crustpunk`).
- Existing dispositions stay: `hide` (non-music), `block` (junk), alias/`canonical_id`
  (merge). **"Assign to style" becomes "set parent."**
- Curation **queue** = in-use genres with no parent and no disposition ("unplaced").
- **Removed:** `Style` model, `Style↔Genre` HABTM, `styles` taggings on events,
  `Event#recompute_styles!`'s style derivation, `Genre.styles_for`, the admin styles pages.

### Saved filter (generalises `NotificationRule`)
- Holds a `Filter` (`genres` [tree-expanding, exact], `queries` [freetext substring],
  `locations` [exact], `date_ranges`). The current `style_list` slot becomes `genres`.
- **Notification is optional**: a saved filter with notify off is a pure scope/interest;
  with a schedule on, it's today's rule. Schedule/channel validations become conditional
  on notify-enabled. `no_duplicate_filter` (one per fingerprint) becomes the Save-dedup.
- Identity = filter-content fingerprint. Save is idempotent; unsave removes.

### Mechanics
- **Filter by a genre** = match the genre OR any descendant (expand to a name/id set,
  exact match). Replaces both the old `s[]` style bucket and the `q[]` substring hack
  with a reliable rollup. Typed freetext still substrings.
- **Highlight** a row genre tag iff its genre is in the active filter's expanded set
  (set membership; the set is already built for matching). Tapping a lit subgenre
  removes the ancestor term that lit it (current toggle semantics).
- **Music gate**: event hidden iff it has no non-hidden genre (reads dispositions
  directly; no styles).
- **★ / 🔔**: ★ saves/unsaves the current (or one-term picker) filter; 🔔 saves +
  enables notifications. Both buttons; lit = that exact content is saved / notifying.
- **"My interests" & calendar** = OR-union over the user's saved filters.

## Feature verification

| Feature / principle | New behaviour | Status |
|---|---|---|
| Browse what/where/when | Genre tree (big-first) + location + dates | ✓ improved |
| Tap-to-filter on a row | Tap genre → filter by it + descendants | ✓ simpler |
| Fluid follow while browsing | One-tap ★ in picker (one-term saved filter) | ✓ |
| "My interests" | OR-union of saved filters (derived) | ✓ |
| Calendar interest markers | Event matches any saved filter | ✓ (heavier match, see perf) |
| Notifications | Saved filter + schedule (today's rule) | ✓ exists |
| Music-focus exclusion | Hidden iff no non-hidden genre | ✓ equivalent |
| Admin curation | Parent genres; hide/block/alias unchanged | ✓ simpler |
| Scrapers | Tag raw genres; new ones arrive unplaced | ✓ unchanged |
| Saved shows / privacy / accounts | Untouched | ✓ |

**Perf to design for:** subtree expansion via a cached `descendant_ids` (or recursive
CTE); calendar interest-marking becomes "does this event match any saved filter,"
batched per filter over the visible window rather than a set lookup. Bounded, but real.

## Phased implementation plan

Each phase is independently shippable and testable.

- **Phase 0 — Seed bootstrap (tooling). ✅ DONE.** `rake taxonomy:draft_tree` reads
  `lib/genres.json` + `genre_aliases.json` + `genre_dispositions.json` and emits
  `db/genres.yml` (styles → roots, their genres → children, deduped by fingerprint;
  dispositions/aliases carried over). A first *draft* to cultivate by hand — it is a
  flat dump of today's 15 styles × ~5.7k genres; the real work is nesting/pruning it.
- **Phase 1 — Genre tree. ✅ DONE.** `genres.parent_id` (self-ref FK + not-self check);
  `Genre.subtree_ids` (recursive CTE) / `#descendant_ids`; `Genre#set_parent!` (the
  "assign" → "set parent" reframe, with a cycle guard) clearing dispositions; `unplaced`
  scope = the new curation queue; dispositions/merge/restore detach from the tree; admin
  curation parents via a combobox (`GenresController#set_parent`); idempotent loader
  `GenreTreeSeed` / `rake taxonomy:import_tree`. Style still present, untouched.
  Tests: `genre_tree_test`, `genre_tree_seed_test`, `genres_admin_test`.
- **Phase 2 — Filter on the tree.** `Filter` gains genre tree-expansion (`genres` slot);
  What picker renders the tree big-first; row shows genres only + descendant highlight;
  music gate reads genre dispositions. **Remove `Style`** (model, HABTM, styles
  taggings, derivation, admin pages).
- **Phase 3 — Saved filters.** Generalise `NotificationRule` (notify optional,
  conditional validations); apply/save/manage lifecycle; ★ save + 🔔 notify on the
  filter UI; fingerprint-derived "saved?" state; main page stays ephemeral.
- **Phase 4 — Dissolve interests.** Derive "My interests" + calendar markers from saved
  filters; **remove** `User#style_list`/`location_list`, favorites controller/views,
  `track_favorites`.
- **Phase 5 — Prod reset.** Deploy (schema migrates), run the taxonomy reset task, load
  the cultivated seed, recompute event visibility, re-run a scrape.

## The two concrete operational questions

### 1. Do I need to run manual tasks in prod?

**Yes — one reset, once.** Sequence:

1. **Push to main → Render auto-deploys**, running schema migrations in
   `preDeployCommand` (add `genres.parent_id`; drop `styles`/`genres_styles`; relax
   `notification_rules` so notify is optional; drop `users` favorites columns). Because
   there are no real users, the dropped favorites data needs no migration — it just goes.
2. **In the Render shell, run the reset task once:** `bin/rails taxonomy:reset` — drops
   existing genre/style rows, loads the cultivated tree seed, runs `Genre.reconcile!`,
   and recomputes each event's `hidden` flag from genre dispositions. (Events keep their
   raw `genres` taggings; only `styles` taggings are dropped, by the migration.)
3. **Re-run a scrape** (or wait for the daily cron) so any genres not in the seed arrive
   as unplaced rows in the curation queue.

No per-user cleanup. No taggings/tags truncation beyond the `styles` context (the old
"favorites = user taggings, never truncate" caveat is moot once favorites are gone).

### 2. How does the seed work now?

The seed is a **curated genre tree** (replacing the flat `db/genres.json`), loaded by an
idempotent rake task. Proposed format (`db/genres.yml` or similar):

```yaml
genres:
  - name: Rock
    children:
      - name: Punk
        children: [Crustpunk, Hardcore]
      - Post-Rock
      - Garage Rock
  - name: Metal
    children: [Black Metal, Speed Metal]
  - name: Electronic
    children: [Techno, House, Drum & Bass]

# non-music / junk handled by disposition, not parenting
hidden:  [Fussball, Lesung]
blocked: ["Türöffnung", Eintritt]

# semantic merges the fingerprint can't catch
aliases:
  Elektronik: Electronic
  HipHop: Hip Hop
```

Loader behaviour:
- Upsert a `Genre` per name (matched/deduped by **fingerprint**, reusing `Genre.ensure!`),
  set `parent_id` from the nesting, apply `hidden`/`blocked`/`alias` marks.
- Idempotent — re-running converges (safe to run on every deploy or by hand).
- **Genres not in the seed** (new scrapes) arrive with no parent + no disposition → the
  admin curation queue, where you place them in the tree. The seed is the curated
  backbone; scrapers add leaves you then file.

Phase 0 produces the *first draft* of this file from current data so cultivation starts
from something real, not a blank page.

## Open / deferred

- The "Update 'X'?" session-pointer affordance (decision 8).
- `featured`/`main_genre` flag and subtree-count ranking (decision 6).
- DAG upgrade, only if multi-home genres become painful (decision 1).
- Bell/star button layout polish (both buttons; ★ = save, 🔔 = save+notify).
