# Genre tag clean-reset runbook

Goal: purge the free-text junk genre tags that scrapers minted before the
discovery/consumption split (e.g. `Us`, `Any Stile`, a stray `Salsa Namá` row).
The curated dictionary in `lib/genres.json` (15 styles plus ~5,730 genre-to-style
mappings, derived from the Spotify / Every Noise taxonomy) is **kept and
re-seeded unchanged** — it is the auto-mapper that buckets scraped genres into
styles.

## Why a wipe is needed (a plain re-seed or re-scrape is not enough)

- The discovery/consumption split already stops *new* junk: scrapers without a
  clean structured genre field can no longer create genres.
- But the *existing* junk is already Genre rows. `genres:seed` is additive (it
  creates missing dictionary genres, never deletes), and a re-scrape does not
  help either — `Genre.existing_only` *matches* the junk rows because they still
  exist, so they survive. **You must delete the junk rows.** Wiping and
  re-seeding the dictionary is the simplest way, and it doubles as proof the fix
  works (the junk must not reappear).

Run locally first, verify, then run the identical steps on prod.

## Stage 0 — Backup

Cheap insurance even though the data is disposable.

```bash
pg_dump "$DATABASE_URL" > /tmp/uesgu_backup.sql
```

On prod, take a Render Postgres snapshot instead.

## Stage 1 — Wipe, re-seed, re-scrape (LOCAL)

Keeps `users`, `invitations`, `sessions`. `notifications` reference events, so
they go too (regenerated on the next digest run).

Step 1 — wipe events and the whole taxonomy (CASCADE clears the `genres_styles`
join and any FK):

```bash
bin/rails runner 'ActiveRecord::Base.connection.execute("TRUNCATE events, genres, genres_styles, styles, taggings, tags, notifications RESTART IDENTITY CASCADE;")'
```

Step 2 — rebuild the curated dictionary (styles, genre-to-style map, aliases,
dispositions):

```bash
bin/rails genres:seed
```

Step 3 — re-scrape every venue. Discovery genres auto-map; consumption scrapers
match the dictionary only and cannot mint junk:

```bash
bin/rails scrapers:run_all
```

Step 4 — refresh each event's derived styles and hidden flag:

```bash
bin/rails runner 'Event.find_each(&:recompute_styles!)'
```

## Stage 2 — Verify (this is the confirmation step)

```bash
bin/rails runner '
  puts "events=#{Event.count} genres=#{Genre.count} in_use=#{Genre.in_use.count} unassigned=#{Genre.unassigned.count}"
  %w[Us Salsa\ Namá Any\ Stile Move Groove].each do |name|
    g = Genre.find_by(fingerprint: Genre.fingerprint_for(name))
    puts "  junk #{name}: #{g ? "PRESENT count=#{g.events_count}" : "absent"}"
  end
  %w[techno indie\ rock hip\ hop].each do |name|
    puts "  dict #{name}: #{Genre.exists?(fingerprint: Genre.fingerprint_for(name)) ? "present" : "MISSING"}"
  end
'
```

```bash
bin/rails test
```

Then click through `/`, `/favorites`, and `/admin/genres` and confirm the genre
lists read clean. Discovery scrapers may still surface genuinely-new genres from
clean fields (event-type tags like `Konzert` or `Festival`) — those land in the
assignment queue. Dispose them by adding to `lib/genre_dispositions.json` under
`ignored` or `hidden`, then run:

```bash
bin/rails genres:import_dispositions
bin/rails runner 'Event.find_each(&:recompute_styles!)'
```

## Stage 3 — Repeat on prod

Once local looks right and the branch is merged and deployed (prod scrapers need
the split live), run Stage 1 and Stage 2 verbatim on the Render shell. Users,
invitations, and sessions are untouched throughout.

## Alternative — targeted cleanup without wiping events

If you ever want to keep events (not a concern in alpha), delete only the
unmapped junk instead of wiping.

Ensure the dictionary exists:

```bash
bin/rails genres:seed
```

Delete in-use genres that are not in the dictionary and not curated/disposed
(unmapped == not in the dictionary), then drop orphaned tags:

```bash
bin/rails runner '
  Genre.in_use
       .where(ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil)
       .left_joins(:styles).where(styles: { id: nil })
       .destroy_all
  ActsAsTaggableOn::Tag.where("id NOT IN (SELECT DISTINCT tag_id FROM taggings)").delete_all
'
```

Recompute derived styles:

```bash
bin/rails runner 'Event.find_each(&:recompute_styles!)'
```

The wipe (Stage 1) is cleaner and self-verifying, so prefer it while data is
disposable.

## Notes

- `scrapers:run_all` hits ~15 live venues sequentially (a few minutes); a flaky
  venue may fail its section without aborting the run.
- Order matters: `genres:seed` (styles must exist before genres map to them),
  then `scrapers:run_all`, then recompute.
- Keep `users`, `invitations`, `sessions`. Everything else is regenerated.
