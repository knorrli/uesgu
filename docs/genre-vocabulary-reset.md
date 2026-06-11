# Genre tag clean-reset runbook

Goal: purge the free-text junk genre tags that scrapers minted before the
discovery/consumption split (e.g. `Us`, `Any Stile`, a stray `Salsa Namá` row).
The curated dictionary in `lib/genres.json` (15 styles + ~5,747 genre→style
mappings, derived from the Spotify/Every-Noise taxonomy) is **kept and re-seeded
unchanged** — it's the auto-mapper that buckets scraped genres into styles.

## Why a wipe is needed (and a plain re-seed/re-scrape is not enough)

- The discovery/consumption split already stops *new* junk: scrapers without a
  clean structured genre field can no longer create genres.
- But the *existing* junk is already Genre rows. `genres:seed` is additive (it
  creates missing dictionary genres, never deletes), and a re-scrape doesn't help
  either — `Genre.existing_only` *matches* the junk rows because they still exist,
  so they survive. **You must delete the junk rows.** Wiping + re-seeding the
  dictionary is the simplest way, and it doubles as proof the fix works (the junk
  must not reappear).

Run locally first, verify, then run the identical steps on prod.

---

## Stage 0 — Backup (cheap insurance; data is disposable but still)

```bash
pg_dump "$DATABASE_URL" > /tmp/uesgu_backup.sql   # local; on prod use a Render Postgres snapshot
```

Optional: drop the two known seed contaminants while you're here.
```bash
# remove the lines "berner mundartrock" and "salsa namá" from lib/genres.json, then commit
```

---

## Stage 1 — Wipe + re-seed + re-scrape (LOCAL)

Keeps `users`, `invitations`, `sessions`. `notifications` reference events, so
they go too (regenerated on the next digest run).

```bash
# 1. wipe events + the whole taxonomy (CASCADE clears the genres_styles join + any FK)
bin/rails runner '
  ActiveRecord::Base.connection.execute(
    "TRUNCATE events, genres, genres_styles, styles, taggings, tags, notifications RESTART IDENTITY CASCADE;"
  )
  puts "wiped — genres=#{Genre.count} events=#{Event.count} users=#{User.count} (preserved)"
'

# 2. rebuild the curated dictionary (styles + genre→style map + aliases + dispositions)
bin/rails genres:seed

# 3. re-scrape every venue (discovery genres auto-map; consumption matches the dictionary only)
bin/rails scrapers:run_all

# 4. refresh each event's derived styles + hidden flag
bin/rails runner 'Event.find_each(&:recompute_styles!)'
```

---

## Stage 2 — Verify (this is point 7: confirm the junk is gone)

```bash
bin/rails runner '
  puts "events=#{Event.count}  genres total=#{Genre.count}  in-use=#{Genre.in_use.count}  unassigned=#{Genre.unassigned.count}"
  # the free-text junk must be ABSENT (no row, or zero usage):
  %w[Us Ch Au Salsa\ Namá Any\ Stile Move Groove].each do |j|
    g = Genre.find_by(fingerprint: Genre.fingerprint_for(j))
    puts "  #{j.ljust(12)} #{g ? "PRESENT events_count=#{g.events_count}" : "absent ✓"}"
  end
  # the dictionary must be PRESENT:
  %w[techno indie\ rock hip\ hop].each do |k|
    puts "  dict #{k.ljust(10)} #{Genre.exists?(fingerprint: Genre.fingerprint_for(k)) ? "present ✓" : "MISSING"}"
  end
'
bin/rails test
```

Then click through `/`, `/favorites`, `/admin/genres` and confirm the genre lists
read clean. Discovery scrapers may still surface genuinely-new genres from clean
fields (e.g. event-type tags like `Konzert`, `Festival`) — those land in the
assignment queue; dispose them via `lib/genre_dispositions.json` (`ignored`/
`hidden`) + `bin/rails genres:import_dispositions`, then re-run the recompute line.

---

## Stage 3 — Repeat on prod

Once local looks right and the branch is merged/deployed (prod scrapers need the
split live), run **Stage 1 + Stage 2** verbatim on the Render shell. Users,
invitations, and sessions are untouched throughout.

---

## Alternative — targeted cleanup without wiping events (if ever needed)

If you don't want to drop events (not a concern in alpha, but for later):

```bash
bin/rails runner '
  bin/rails genres:seed   # ensure the dictionary exists
  # delete in-use genres that are NOT in the dictionary AND not curated/disposed
  Genre.in_use
       .where(ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil)
       .left_joins(:styles).where(styles: { id: nil })   # unmapped == not in dictionary
       .destroy_all
  ActsAsTaggableOn::Tag.where("id NOT IN (SELECT DISTINCT tag_id FROM taggings)").delete_all
'
bin/rails runner 'Event.find_each(&:recompute_styles!)'
```

This drops the unmapped junk while keeping events and the dictionary. The wipe
(Stage 1) is cleaner and self-verifying, so prefer it while data is disposable.

## Notes

- `scrapers:run_all` hits ~15 live venues sequentially (a few minutes); a flaky
  venue may fail its section without aborting the run.
- Order: `genres:seed` (styles must exist before genres map to them) → `run_all`
  → recompute.
- Keep `users`, `invitations`, `sessions`. Everything else is regenerated.
