# Genre vocabulary clean-reset runbook

Goal: replace the bloated genre vocabulary (~5800 rows, mostly junk minted from
prose/artist-names over time) with a clean one. Run it **locally first**, verify,
then repeat the identical steps on prod.

## Why this is now easy

The discovery/consumption split (branch `scraper-discovery-consumption-split`)
means consumption scrapers (docks, mahogany_hall) can only *match* existing
genres — they never create. So **scraping against an empty genre table mints
only discovery-scraper genres** (the clean, structured sources). The bootstrap is
automatic: `wipe + run_all` produces a clean vocabulary by construction.

Two levels of effort — pick based on how polished you want it:

- **Minimum (mechanical):** wipe → `run_all`. Eliminates *all* consumption
  pollution immediately; you're left with only discovery-source genres (a few
  hundred, not 5800). Good enough to ship.
- **Polish (judgment, iterative):** curate that smaller set — map genres to
  styles, block/hide/ignore the event-type leftovers ("Konzert", "E-Sports",
  "Party"). Done on the now-small set via the seed files + `/admin` UI.

## Pre-requisite

The mechanism must be live where you're running this. Locally it's on the branch
already. **For prod, deploy the branch (merge to main) before the prod reset** —
otherwise prod scrapers still run in create-everything mode.

---

## Stage 0 — Backup (both envs; cheap insurance even though data is disposable)

```bash
# local
pg_dump "$DATABASE_URL" > /tmp/uesgu_backup_local.sql
# prod: run from the Render shell, or pull a Render Postgres backup snapshot first
```

Also snapshot the current seed inputs so you can diff later:
```bash
cp lib/genres.json /tmp/genres.json.before
```

---

## Stage 1 — Bootstrap the candidate vocabulary (LOCAL)

Wipe the taxonomy + events (keeps `users`, `invitations`, `sessions`), then let
the scrapers repopulate. `notifications` reference events, so they go too
(regenerated later).

```bash
bin/rails runner '
  ActiveRecord::Base.connection.execute(
    "TRUNCATE events, genres, genres_styles, styles, taggings, tags, notifications RESTART IDENTITY CASCADE;"
  )
  puts "wiped. genres=#{Genre.count} events=#{Event.count} users=#{User.count}"
'
```

Re-seed the **styles** taxonomy (so discovery genres can map as they appear) and
scrape:
```bash
bin/rails genres:seed       # styles + current aliases/dispositions from lib/*.json
bin/rails scrapers:run_all  # discovery genres minted; consumption matches the seed only
```

> Note: `genres:seed` still imports today's bloated `lib/genres.json`. That's
> fine for the bootstrap — `run_all` + `reconcile!` only keep genres actually in
> use (`events_count > 0`). The unused seed bloat stays dormant and is dropped
> when you rebuild the seed in Stage 2. If you want a *pure* discovery bootstrap
> with nothing pre-seeded, skip `genres:seed` here and run only `scrapers:run_all`.

Inspect what the clean set looks like:
```bash
bin/rails runner '
  rows = Genre.in_use.by_usage.pluck(:name, :events_count)
  puts "in-use genres: #{rows.size}"
  rows.first(80).each { |n, c| puts "  #{c.to_s.rjust(4)}  #{n}" }
  puts "unassigned (no style yet): #{Genre.unassigned.count}"
'
```

This list is the candidate vocabulary. If you stop here, you already have a
clean, pollution-free taxonomy.

---

## Stage 2 — Curate into new seed files (JUDGMENT — do together)

Turn the candidate set into durable seed files so the reset is reproducible.

1. **Export the current in-use set with any style mapping it already has** (lets
   us reuse prior curation instead of redoing it):
   ```bash
   bin/rails runner '
     require "json"
     data = Genre.in_use.includes(:styles).map { |g|
       { name: g.name, count: g.events_count, styles: g.styles.map(&:name),
         disposition: (g.blocked? ? "blocked" : g.hidden? ? "hidden" : g.ignored? ? "ignored" : nil) }
     }
     File.write("/tmp/candidate_vocab.json", JSON.pretty_generate(data))
     puts "wrote #{data.size} genres to /tmp/candidate_vocab.json"
   '
   ```
2. **Curate** `/tmp/candidate_vocab.json` → rebuild the three seed files:
   - `lib/genres.json` — `{ "Style Name": ["genre", "genre", …] }`. Keep only
     real genres; assign each to a style. (I can draft this from the candidate
     export — most already carry a style from the old mapping; you review the
     unmapped and the merges.)
   - `lib/genre_aliases.json` — `{ "Canonical": ["variant", …] }` for semantic
     merges the fingerprint can't catch.
   - `lib/genre_dispositions.json` — `{ "blocked": […], "hidden": […],
     "ignored": […] }`. This is where event-type leftovers go: "Konzert",
     "Party", "Public-Viewing", "E-Sports", "Daydance", "Festival" → `ignored`
     (or `hidden` for non-music); origin codes → `blocked`.
3. Commit the new seed files.

This is the only irreducible manual step, and it's now over a few hundred genres,
not 5800.

---

## Stage 3 — Clean reset with the curated seed (LOCAL) + verify

```bash
bin/rails runner '
  ActiveRecord::Base.connection.execute(
    "TRUNCATE events, genres, genres_styles, styles, taggings, tags, notifications RESTART IDENTITY CASCADE;"
  )
'
bin/rails genres:seed                                   # curated taxonomy + aliases + dispositions
bin/rails scrapers:run_all                              # consumption now matches the curated vocab
bin/rails runner 'Event.find_each(&:recompute_styles!)' # refresh derived styles + hidden flags
```

Verify:
```bash
bin/rails runner '
  puts "events=#{Event.count} genres(in use)=#{Genre.in_use.count} unassigned=#{Genre.unassigned.count}"
  puts "styles=#{Style.count} hidden events=#{Event.where(hidden: true).count}"
  # spot-check: no origin codes / obvious junk minted
  %w[Us Ch Au Salsa].each { |j| g = Genre.find_by(fingerprint: Genre.fingerprint_for(j)); puts "#{j}: #{g ? "PRESENT (#{g.events_count})" : "absent ✓"}" }
'
bin/rails test
```

Click through the local site (`/`, `/favorites`, `/admin/genres`) and confirm the
genre lists look clean. Any stragglers → add to `genre_dispositions.json` and
re-run `genres:import_dispositions` + the recompute line.

---

## Stage 4 — Repeat on prod

Once local looks right and the branch is merged/deployed:

1. **Export prod's current DB curation first** (in case admin-UI dispositions/
   style-maps were set on prod but never written back to the seed files):
   ```bash
   # on the Render shell
   bin/rails runner '<the candidate_vocab.json export from Stage 2.1>'
   ```
   Reconcile any prod-only curation into the committed seed files, redeploy.
2. Run **Stage 3** verbatim on the Render shell (it already includes the wipe).
3. Verify with the same checks. Users/invitations/sessions are untouched
   throughout.

---

## Rollback

```bash
psql "$DATABASE_URL" < /tmp/uesgu_backup_local.sql   # local
# prod: restore the Render Postgres snapshot from Stage 0
```

## Notes / gotchas

- `scrapers:run_all` hits ~15 live venues sequentially and can take a few minutes;
  a flaky venue (e.g. Bad Bonn) may fail its section without aborting the run.
- Order matters: `genres:seed` (styles must exist) → `run_all` → recompute.
- `genres_styles` is the HABTM join; `TRUNCATE … CASCADE` clears it automatically.
- Keep `users`, `invitations`, `sessions`. Everything else is regenerated.
