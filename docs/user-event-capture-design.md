# User event capture — design decisions and model evaluation

> Status: **decided; the schema prerequisites, the contributor flag and the
> extraction service are built** (2026-08-19) — decisions 4–6 shipped as the
> `places` table plus the location taxonomy reading it, decision 10 as the nullable
> `events.url`, the `users.contributor` half of decision 7, and the extract half of
> the funnel as `EventCapture` (see "Provider evaluation"). Everything else (the
> three adapters, the verify screen, VenueLead nomination) is still design only.
> Supersedes the framing in
> [`user-event-capture.md`](user-event-capture.md), which stays as the original
> idea note. This document records what we settled on and the evidence behind the
> provider choice, so neither gets re-litigated.

## Why

üsgu's promise is "you won't miss a show". The honest version is *"…at a venue we
scrape"*. Aggregators are tapped out (see
[`open-event-data-research.md`](open-event-data-research.md)), and the long tail —
house shows, one-offs, tiny rooms, grapevine tips — is unreachable by scraping in
principle. Manual capture attacks coverage from the **demand side**: people surface
the events they personally bump into.

Concrete measure of the gap: of six real samples collected in one week (four
posters, two WhatsApp screenshots), **one** was at a venue in `config/venues.yml`.

## The feature

One capture funnel, three input adapters — **URL**, **image**, **pasted/screenshot
text** — feeding a shared *extract → verify → create* path.

### Decided

1. **Bulk-first.** Upload N images, extract all, review them on one screen with
   per-candidate accept/edit/drop. Single capture is just N=1.

   **Extraction is one request per image, driven by the client — no job queue.**
   The constraint is real (you cannot hold a request open for eight vision calls),
   but "async" was the wrong conclusion drawn from it. There is no async substrate
   to reach for: `config.active_job.queue_adapter = :inline`, `app/jobs/` holds
   only `ApplicationJob`, and `render.yaml` runs one web service plus two crons —
   Solid Queue was deliberately removed because it competed with Puma for RAM.

   Gemma measures 2.3s, so the problem is never 2.3s, only 8 × 2.3s in one
   request. Upload all N, then fire one extraction request per image and fill the
   verify list progressively via Turbo Streams. No worker service, no queue, no
   cron latency in an interactive flow, and a failed image is one row to retry
   rather than a dead batch. At ~5 captures/day the thread pressure is nil.

   Rejected: a Render worker service (money, and it re-adds what was removed), and
   a DB-backed queue drained by cron in the shape `notify-due` uses (free, but
   minutes of latency is the wrong trade for a screen someone is waiting on).

2. **The unit is 0..n events per input, not one.** A poster can advertise two
   concerts; a festival timetable three acts. Both occur in the sample set.

3. **Place splits into two kinds — which we never classify**, and the venue
   registry is *not* extended automatically:
   - `Venue` (`config/venues.yml`) keeps its current meaning — **venues we source
     from**. Still closed, still PR-approved. It cannot be written at runtime
     anyway: it is a code file, `main` is PR-gated, deploys are tag-gated, and
     Render's filesystem is ephemeral.
   - Captured events get a DB-backed place. Some of those are real venues, some
     are ad-hoc (Marzili Quartierfest, "Konzert im Kocherpark") — but the
     distinction is *emergent*, never recorded at capture time. See "VenueLead
     promotion".
   - `Location.type_for` must consult both. **Built.** It classified anything
     unknown as a **locality** (`app/models/location.rb`), so a captured "ZAR"
     read as a locality in the filter chips, the location combobox suffix, and the
     admin browser, and could not reach the WHERE *tree* at all
     (`Location.hierarchy` was built purely from `Venue.in_taxonomy`). Both halves
     now union the registry with `Place`, registry first.
   - The same registry-derivation bug bit cantons, independently of capture:
     `Location.canton_codes` was the set the *registry* covers, so a tag for an
     uncovered canton ("VS") typed as a city. **Fixed in #95** — `CANTON_CODES` is
     now the closed list of 26, locked to the `cantons:` locale map by a test. Only
     the venue half of `type_for` still needs the capture work.
   - A place that keeps recurring becomes a **`VenueLead`** — the existing
     discovery inbox at `/admin/venue_leads`, which already ranks by
     `event_count`. Capture three events at ZAR and it rises in the inbox; that is
     the signal to write a scraper and add the YAML row by PR. Auto-add is
     replaced by auto-*nominate*.

4. **Captured places join the WHERE tree**, under canton > locality > place, the
   same as a registry venue. Free-name filtering already works —
   `Filter#location_list=` passes names straight to `locations_name_in` without
   validating against the taxonomy — but "reachable if you type the exact name"
   is not findable, and findability is the whole point of capturing the event.
   `Location.hierarchy` unions a places-derived tree onto the registry-derived
   one; it is roughly five lines against the existing `add_to_tree`.

   The usual objection — one-offs cluttering a permanent-looking tree — is
   already answered: `location_filter_tree` prunes every node to what events
   currently carry, so a captured place drops out of the tree by itself once the
   show has passed. Nothing expires it manually.

   **Built** — `Location.hierarchy` folds `Place.pluck(:canton, :locality, :name)`
   onto the registry tree through the same `add_to_tree`, and it did land at
   roughly the estimated size.

5. **Place-name normalisation uses the genre fingerprint pattern** — the stored
   generated column that folds case, spacing, punctuation and umlauts, plus
   `canonical_id` for alias-merge. Its reach is limited: it collapses
   `MARZILI`/`Marzili` but not `Quartierfest`/`Quarterfest` or
   `Schützenmatt`/`Schützenmatte`. **The real defence is match-at-entry** — the
   verify UI offers existing places that fingerprint-near the extracted name and
   the user taps one. Fingerprint + admin merge is the safety net, not the plan.

   **The fingerprint half is built**: a stored generated column on `places`,
   character-identical to the genres one, with the Ruby reproduction extracted to a
   shared `Fingerprint` so there is one normalizer rather than two copies drifting.
   `Place.matching` resolves a raw name and follows a merge to its canonical.
   Match-at-entry itself is not built, and there is no admin merge UI. The *near*
   half is now decided — see "Matching at entry" below.

6. **Canton and locality are both required.** The earlier version of this
   decision made the middle tier optional, reasoning that a concert in a forest
   between Bern and Luzern has no *city*. Decision 4 kills that: `add_to_tree`
   bails on a blank middle tier (`return if canton.blank? || locality.blank?`), so a
   place without one cannot be a tree node. Optional means the events most likely
   to need the tree — the forest, the field, the barn — are the ones silently
   missing from it.

   The reframe that makes it answerable: the field is not "city", it is **the
   next level of detail below canton** — a city, a town, a village, a hamlet, a
   quarter. Every point in Switzerland has one. This is not a broadening: the
   registry's 16 distinct values already include Wabern (a village inside
   Gemeinde Köniz), Rubigen (~3k), Düdingen and Kriens. The field has been
   holding localities since the registry shipped; only its name says otherwise.

   Canton stays a closed list (the 26); locality is free text with suggestions
   from existing tags. Same closed-where-finite / open-where-not rule as venues
   vs genres.

   **Required at persist, not at extract.** The model must still be allowed to
   return a null locality alongside its `place_evidence`. Making it mandatory in
   the extraction contract would push fabrication into the exact field
   match-at-entry depends on — and Mistral's four spellings of "Marzili" show
   what a dirty place field costs. The verify screen requires it before the event
   can be created; that is "a null gets completed by a human in one tap" applied
   to the field with the most to lose. When the human genuinely does not know,
   the answer is the nearest named settlement ("Schwarzenburg"), not a blank: a
   slightly-wrong tree node instead of an unreachable event, and it self-prunes
   when the show passes.

   The NOT NULL lands on the captured-place table only. `Venue` stays
   placeless-tolerant — the Bewegungsmelder aggregator row has no place and
   `in_taxonomy` correctly excludes it. **Built** as written: both columns are
   `NOT NULL` on `places`, canton is validated against the closed 26, and `Venue`
   is untouched. A venue can be a sourcing record that is
   not a location; a captured place exists *only* to be a location.

   **Prerequisite: rename `city` → `locality` first, everywhere, as its own
   `chore/` PR (issue #93). Landed in #99** — the attribute *and* the type symbol
   (`type_for` returns `:locality`), so no half-rename survives. Not cosmetic — the extraction prompt is a consumer of this
   name: ask Gemma for a `city` and it will try to produce a city and null out on
   a hamlet, which is the failure mode this decision exists to remove.
   `locality` over the alternatives — `municipality` means Gemeinde and would
   reject "Wabern", which we already store; `town` still implies a size; `place`
   collides with the place model. DE **Ort**, FR **localité**. The half-rename is
   the worst option (a new table saying `locality` next to `venues.yml` saying
   `city` splits one hierarchy tier across two names), so it is all or nothing.
   There is no data migration — location tags are just names and do not change.

7. **Captured events go live immediately**, and a report **quarantines the event,
   not the person**. Contributors are admin-enabled, so the abuse surface is
   ~zero; the realistic report is "this date is wrong" or "this got cancelled".
   Auto-suspending a user on one report is a griefing vector and punitive
   machinery for people you personally approved. Reports from signed-in users
   only. Framing is *"stimmt etwas nicht?"*, not an abuse report.

   Capture is gated by a new **`users.contributor` boolean** — a *capability*,
   deliberately not a role. Today the model is two-level (`users.admin` →
   `User#admin?` → `Admin::BaseController`), everyone else is a regular user, and
   `users` already carries capability-shaped booleans like `event_reminders`. A
   flag sits beside `admin`; a role hierarchy would be machinery for a site whose
   users you personally invited.

   **Built** — the column, `User#contributor?`, and a toggle on
   `/admin/users/:id`. The report/quarantine half is still design only.

8. **Captured events live outside the scraper's re-derivation domain.**
   `Scrapers::Agent#build_event` re-derives every field from source nightly and
   `find_or_initialize_by(url:)` resurrects deleted rows. A captured event has no
   source to re-derive from, and `events.url` is `NOT NULL` + unique while a
   poster has no URL (decision 10 makes it nullable). Use the existing
   `data_source` column as the seam. When a venue later gains a scraper, the
   duplicate is handled by `canonical_event_id`.

9. **No image is stored.** Processed then discarded, consistent with the rejected
   `image` field (see [`richer-fields-proposal.md`](richer-fields-proposal.md)).
   The verify screen doubles as the PII checkpoint: the human sees, and edits,
   exactly what will be persisted.

10. **`events.url` becomes nullable, and a capture keeps ONE url column.**
    **Built** as written — the column is nullable, `validates :url` is
    `allow_nil`, the card branches, and `OFFSITE_SOURCES` carries the social
    hosts. Nothing writes a NULL yet; this is the seam, opened ahead of the
    funnel. The column is not the dedup key, which is what made this look hard.
    It is the *scraper's upsert key* — `find_or_initialize_by(url:)` (`agent.rb:269`) — so a
    nightly re-scrape updates last night's row instead of creating a second. Real
    dedup is `Scrapers::Dedup`, grouping on venue + date + fuzzy title and linking
    losers via `canonical_event_id`; it never keys on `url`, and its own header
    describes cleaning up *after* URL-identity fails (a scraper's scheme change
    stranding the old-keyed copy — Mokka #55, Südpol #56). A captured event
    therefore loses nothing by having no URL, and per decision 8 nothing
    re-derives it, so it needs no upsert key at all: a human creates it once and
    edits it by `id`.

    Rejected the synthetic `uesgu:capture/<uuid>`. Two of the four `event.url`
    readers already refuse a non-http value — `digest_event_href` links only
    `https?://`, `event_offsite_source` parses it to a nil host — so a synthetic
    value would pass review while `events/_event.html.erb` shipped a **dead link
    on every captured event**, rendering fine and failing in the browser. NULL
    forces that line to branch, and the branch is the actual product question the
    synthetic value hides: a captured event's title is not an outbound link.
    Precedent for identity-without-a-URL is already in `SavedEventsCalendar`,
    which builds its stable uid from `event.id` — "just the identifier namespace
    here, not a routable link".

    The migration is cheap, contrary to the earlier framing of this as "a
    migration on the busiest table": dropping a NOT NULL is catalog-only in
    Postgres, no rewrite and no scan — it is *adding* one that hurts. No partial
    index is needed either, since a Postgres unique index already permits
    unlimited NULLs (`NULL != NULL`), so `index_events_on_url` stands untouched.
    Only `validates :url, presence: true` becomes conditional — `allow_nil`, which
    keeps rejecting `""`: an empty string is a third state, and it is one the
    unique index *does* compare, so the second url-less event would fail to save.

    **No separate `source_url`.** Where a pasted link *is* the venue's own event
    page, colliding with the scraper's key is the point: the scraper adopts the
    captured row, which keeps its `id` — so saves, reminders and notification
    history survive — while the data upgrades to maintained. `data_source` flips
    to the scraper, which is correct; it is scraped now. That is the best outcome
    available, not a defect. It is also self-limiting: pasting a URL that already
    exists fails the unique index, which is precisely the "this event already
    exists" the verify screen should say. A second column would let that duplicate
    through. Keeping the paste as *evidence* was rejected on decision 9's
    precedent — an image capture already retains zero provenance, so a column that
    preserves it for the easier case only is asymmetric.

    **A social or ticketing paste does populate `url`** — reluctantly. We would
    rather not send people to Instagram, but for the ad-hoc events this feature
    exists to catch it is regularly the only page that exists, and a link that
    sets expectations beats no link at all. `OFFSITE_SOURCES`
    (`app/helpers/events_helper.rb`) gains `instagram.com` / `facebook.com` rows
    so the card badges where the link lands — the mechanism already built for
    "this link leaves you at Bewegungsmelder, not the venue". Adoption only ever
    fires when the paste was the venue's own page, so social-sourced captures keep
    their link permanently; the badge is what keeps that honest.

### The place model

> **Built.** `app/models/place.rb`, `db/migrate/20260819160000_create_places.rb`,
> and the `Location` changes that read them. Nothing writes a `Place` yet outside
> tests — the capture path that would is still design only.

A new `places` table, scoped as the **complement** of `Venue` — not a superset and
not a mirror. A registry venue never gets a `Place` row: if the extracted name
matches `config/venues.yml`, the event just carries the tag. `places` holds only
what the registry does not cover.

The jobs it has to do, which are what picks the shape: classify a name so
`Location.type_for` stops guessing; carry canton + locality for a place the
registry never heard of; offer fingerprint-near candidates for match-at-entry
(decision 5); nominate a venue-kind place into `/admin/venue_leads`; and survive a
merge without rewriting events. None of those need the place to own events — it is
a *vocabulary with attributes*, which is exactly what `Genre` already is.

```
places
  name          not null
  fingerprint   stored generated column — same expression as genres (unique)
  locality      not null
  canton        not null
  url           nullable — the venue's own URL when the capture carried one
  canonical_id  self-FK, alias-merge
  check canonical_id <> id
```

There is deliberately **no `kind` column**. See "VenueLead promotion" for why the
venue/ad-hoc distinction is derived from event count rather than stored.

No `place_id` on `events`. Events keep carrying `[name, locality, canton]` as flat
tags, because `Filter#ransack_query` matches `locations_name_in` against tag names
— that is what makes a captured event findable at all. Counts come from the
taggings, the way `Location.usage` already does it. The cost is that correcting a
place's canton later does not move already-tagged events, but that is a retag pass
over `Event.tagged_with(name)` either way; an FK would only change how you find
them, at the price of a column and a divergence from how the app already locates
events by place.

`Location.type_for` returns `:venue` for every place, ad-hoc included — an ad-hoc
place *is* where the thing happens, and `Event#venue` picking it up is what makes
the card render. This keeps the type vocabulary at three and avoids a three-locale
copy change for a distinction that is ours, not the user's.

`url` earns its column twice over. It makes match-at-entry **exact**: the registry
is keyed by `domain`, so a capture carrying `zar.ch` resolves to the ZAR row even
when the poster spells the name "Z.A.R." and fingerprint-near matching would miss.
And it makes a lead *actionable* — the human's next move on a lead is "write a
scraper", which needs a URL. The WhatsApp sample, where the venue is identifiable
only from a URL, is the case that proves it is often available.

Rejected:

- **A table that also mirrors the registry venues.** That is `VenuePlace` again —
  the table that fed the location taxonomy until PR #29 retired it precisely
  because two sources of "what is a venue" drift. `Location` reads the registry
  first, then `Place`; two disjoint sets, one precedence rule.
- **Extending `VenueLead`.** It already has `venue/locality/canton/event_count`, but
  `refresh!` is `delete_all` + reinsert per source — correct for a run-scoped
  discovery snapshot, fatal for a record live events depend on. `VenueLead` stays
  the *inbox*; nomination is a projection into it (see decision 3).
- **Fields on `Event`.** No dedup surface, no suggestion list for match-at-entry,
  nothing to merge.

Registry collisions run in **two directions, and only one of them can gate the
build**. Forward — capturing a place we already source from — is a validation on
`Place`, matched by fingerprint so a variant spelling cannot slip past. Both
directions are drawn at `Venue.in_taxonomy` rather than at the whole file, which is
what makes the caveat under "Rejecting a lead" work: a `disposition: reject` row
and a `Place` for the same name coexist deliberately, and neither the validation
nor the drift report objects. Backward
— a captured venue graduating to a YAML row — is not reachable by a test at all:
the ledger drift test works because both of its sides are files in the repo, and
these rows live in the database, which is empty in CI. So the intended drift test
ships as `bin/rails places:drift` instead — it reports every `Place` the registry
has since absorbed and exits nonzero, which makes deleting the graduated row a
command the graduating PR runs rather than a thing someone remembers.

### Matching at entry

Decision 5 named match-at-entry as the real defence against a dirty place field and
left the mechanism open. This is that mechanism. It is a prerequisite for the
verify screen (#106), not a refinement of it.

The stake is higher than tidiness. A place that splits across three near-identical
rows does not merely clutter the WHERE tree — the tree self-heals when the shows
pass. It breaks the **promotion signal**: nomination fires at `events_count >= 2`
on a `Place` (see "VenueLead promotion"), so three captures spread over
`Quartierfest` / `Quarterfest` / `Marzili Quartierfest` never reach the threshold,
and a real venue stays invisible in the discovery inbox forever. The one failure
mode with no self-correcting path is the one a split name causes.

#### Trigram similarity, not edit distance

`pg_trgm`'s `word_similarity`, scored in Postgres.

The case that decides it is a **subset, not a typo**: the extracted name is
regularly a fragment of the stored one ("Quartierfest" against an existing "Marzili
Quartierfest"), and Levenshtein scores that pair as wildly distant while trigram
word-similarity scores it near 1.0. Typos are the easier half of the problem and
both approaches handle them; only trigrams handle the half that actually shows up.

The extension is being added for the **measure, not for speed**. `places` is a
tens-of-rows table, so a sequential scan is free and no GIN index is needed up
front — worth stating so nobody later reads the extension as a performance
decision and "optimises" around it.

**Prerequisite, and the one thing that can invalidate this:** confirm
`CREATE EXTENSION pg_trgm` is permitted on Render's managed Postgres. It is
standard contrib and should be, but the whole decision rests on it, and deploy time
is the wrong moment to find out.

#### Two columns, two jobs

The comparison must NOT run on `fingerprint`. The fingerprint strips every
non-alphanumeric, so "Marzili Quartierfest" becomes `marziliquartierfest` — a
single word. `word_similarity` matches the query against *words* in the target, so
with the boundaries gone it degrades to roughly plain `similarity` (~0.65 on that
pair instead of ~1.0), throwing away the exact property that chose trigrams over
edit distance.

So a second stored generated column beside it, per compared field:

```
places
  name              not null
  fingerprint       stored generated (unique)  — exact identity: the unique index,
                                                 Place.matching, the drift check
  name_folded       stored generated           — case + accents folded, separators
                                                 collapsed to single spaces
  locality          not null
  locality_folded   stored generated           — same rule, same job
  canton            not null
```

The difference is one clause: the fingerprint folds separators **away**, the folded
form folds them **to spaces**. Same `translate()` over the fixed accent set the
fingerprint already uses — `unaccent` is not IMMUTABLE and STORED requires it (see
`AddFingerprintToGenres`). Both columns are generated, so neither can drift from
the other or from the name they derive from.

#### Locality gets the same treatment, and still no table

Locality has the identical splitting failure mode and, unlike the place name, no
normalization at all today: `places.locality` is a plain string and
`Location.hierarchy` groups on the literal value, so "Zorpwil" and "zorpwil" are two
tree nodes. The registry stays clean only because its rows are PR-reviewed; the
captured half has no such gate.

It gets `locality_folded` and the same scoring, and it does **not** get a table.
Decision 6 made locality free text deliberately — closed-where-finite,
open-where-not — and a `localities` registry would reopen that for no gain.

The candidate set spans two sources: captured localities in `places`, and the
registry's 16 distinct values from `Venue.in_taxonomy`. They merge into **one query**,
with the registry side passed as a `VALUES` list built in Ruby, so there is a single
scoring path rather than one SQL implementation and one in-memory implementation
that quietly disagree at the threshold.

#### Rules that hold whatever the threshold turns out to be

- **A suggestion never auto-applies.** The contributor taps one. A near-match must
  not silently rewrite what the model extracted — same spirit as the genre alias
  rule, where a match is a link and never a rewrite of the source data.
- **Candidates include registry venues, not only places.** The most valuable
  outcome of match-at-entry is "this is actually Dachstock": tag the event and
  create no `Place` row at all. A suggestion list that only offers captured places
  cannot produce it.
- **A carried URL short-circuits the whole thing.** The registry is keyed by
  `domain`, so a capture carrying `zar.ch` resolves to the ZAR row exactly, even
  when the poster spells the name "Z.A.R." and no similarity measure would reach it.
- **The threshold is tuned, not guessed.** `script/event_capture_bakeoff.rb` and
  `script/event_capture_bakeoff_truth.json` still hold the six real samples,
  including the one that produced four spellings of "Marzili". Start near 0.4 and
  fit it to those.

Rejected:

- **Levenshtein** (`fuzzystrmatch`). Loses the subset case above, which is the
  common one; also punishes length differences and word reordering, both of which
  a poster produces routinely.
- **Scoring in Ruby** over `Place.pluck`. Tempting at this table size and it needs
  no extension, but it would have to reimplement trigram similarity to match the
  subset case, and the locality path would then have two scoring implementations
  across two sources. One measure, one place.
- **A `localities` table.** See above — it reopens a decision 6 settled, to
  normalize a field that a generated column normalizes for free.

### VenueLead promotion

#### How leads are produced today

Worth writing down, because the inbox reads as broken when it is merely drained.

`config/venues.yml` does not configure which venues an aggregator crawls — it
configures **one feed URL**. Bewegungsmelder's single feed emits events for every
venue it covers, each with its own `<location>`, so the aggregator sees well beyond
the registry. What the registry gates is whether we *keep* what it sees. Per run:

1. `locations_for` (`ole.rb:369`) resolves each event's `[venue, locality, canton]`
   from the feed's `<location>`, canton derived from the PLZ via `SwissPostcode`.
2. `note_place(locations, rows.size)` (`ole.rb:293`) tallies that tuple in memory,
   but only `if rows.any?` — only when the event has an upcoming show. In-memory
   only, so the read-only dry parse stays read-only.
3. `skip_row?` (`ole.rb:255`) is the closed-allowlist gate: under `strict` the
   event is dropped unless `Venue.matching(name)&.consume?`.
4. `persist_leads` (`ole.rb:394`) writes every tallied tuple that `Venue.matching`
   does *not* resolve, via `refresh!` (delete-all-for-source, reinsert).

A lead is therefore: *a venue the feed carried, with an upcoming show, that has no
registry row*. `Venue.matching` searches `all`, not `consuming`, so an
already-rejected or deferred venue is filtered out too — the inbox means "what
have I not yet triaged", not "what am I not ingesting".

**The inbox is empty because it is exhausted, not broken.** Exactly one aggregator
feed is live (BeJazz is `aggregator: true` but `disposition: defer`, and the
shipping loop only generates scrapers for `Venue.consuming`). Of Bewegungsmelder's
venues still posting upcoming events, the live ones — Kulturhof Schloss Köniz and
Heitere Fahne — were both approved on 2026-06-25, so they resolve and their events
are ingested instead of nominated. The empty-state copy already says exactly this.

The consequence that matters here: **`VenueLead` is a mechanism with no fuel.** Its
sole producer is a dying aggregator with nothing left to surface. Capture-sourced
leads would not be an addition to a working queue — they would be the only live
producer.

#### Promotion: don't classify, count

Asking the model "fixed venue or one-off?" walks into the architecture principle
this document closes with ("the model transcribes, code computes"). It is not even
transcription — it is a judgment about the world outside the poster, and
self-reported confidence was already shown to be worthless. Name heuristics
("…fest", "Konzert im …") are the same trap in cheaper clothes: three languages,
silently wrong, no evidence trail.

**Repetition is the definition, not a proxy.** A fixed venue is a place that hosts
events repeatedly. That signal needs no classifier, no prompt and no toggle on the
verify screen — it accumulates on its own, and `VenueLead.by_demand` already ranks
by exactly it. Capture #1 at ZAR is genuinely unknowable; by capture #3 it is
obvious. So nomination is a pure projection, run after each capture (or nightly,
alongside the scrape run):

```
Place (non-registry by construction)
  → no Venue.matching(name), no registry domain match
  → events_count >= 2
  → VenueLead.refresh!(source: "capture", leads: …)
```

Threshold **2**, not 1: a lead's implicit question is "should we write a scraper",
and one event never answers yes. A single-event place stays visible in the admin
locations browser regardless.

The error asymmetry settles the false positives. Marzili Quartierfest reaching the
inbox after three summers costs a human one glance at a list that exists to be
glanced at. A real venue *never* nominated because something classified it ad-hoc
is silent and costs coverage — the entire point of the feature. Over-nominate.

#### Rejecting a lead

Automatic promotion creates a problem the aggregator path never had. `refresh!` is
delete-and-reinsert, so nothing in `venue_leads` can hold a "no thanks"; aggregator
leads age out of the feed, but a capture lead never does, because its count only
grows. A place you have decided against would climb the inbox forever.

The fix needs no new machinery: **rejecting a capture lead is a `disposition:
reject` row in `config/venues.yml`**, with a `reason` — the registry's existing
decision-recording mechanism, PR-reviewed and durable. It already works, because
`Venue.matching` searches every disposition, so filtering nominations through it
drops rejected and deferred venues automatically.

One caveat: a rejected venue then has both a registry row and a `Place` row, so the
drift test proposed above ("fail if a `Place` fingerprint collides with a registry
venue") must allow that case — or the reject row must also retire the `Place`.

#### Two notes to carry

`event_count` will mean two things. For aggregator leads it is *upcoming* events —
"what would this bring us if approved". Capture leads must count events **ever**
captured there, or a lead evaporates as its events pass and the accumulating signal
is destroyed. Same column, two semantics, distinguished by the `source` chip the
view already renders. With the aggregator dormant, capture's meaning becomes the de
facto one; document the column rather than adding a second.

The page needs new copy. `admin.venue_leads.index.intro` and `.empty` both describe
an aggregator-triage queue ("Venues, die ein Aggregator gefunden hat…"). Once
capture is the live producer, the page is the demand-side discovery queue — a
three-locale copy change that belongs in this work, not after it.

### Still open

Nothing. The `events.url` seam was the last one — settled in decision 10.

### The URL adapter

Two questions specific to the adapter that fetches a pasted link server-side.

#### It honours `robots.txt`, and a refusal falls back rather than fails

The argument for exempting it is real: the Robots Exclusion Protocol governs
*automatic* clients — recursive, scheduled, broad retrieval — and this is one
request, no link-following, triggered by a human who is almost certainly looking
at the page in their own browser as they paste it.

It loses to two things. The registry holds venues at `disposition: defer,
reason: robots` (BeJazz, Bird's Eye), and an exempt URL adapter means a
contributor pastes a BeJazz link and we ingest exactly what we decided not to
take — the decision is not overturned, it is routed around by a different door.
And the fetch leaves *our* server with *our* UA, so from the venue's logs it is
indistinguishable from the scraper; "it is really the user's agent" does not
survive contact with how it looks from the other side.

**So: honour it, and degrade instead of refusing.** The funnel already has three
adapters, so a disallowed fetch falls back to the other two — "we can't fetch this
page, paste the text or a screenshot instead". The user pasting text they can
legitimately read is not our automated fetch, it costs one tap, and the coverage
goal survives. A hard refusal is the only genuinely bad outcome, because the long
tail is the entire point of the feature.

Note who this actually affects: the adapter's real target is a house show, a
one-page venue site, a WhatsApp link — places with no `robots.txt` or an
unconsidered CMS default. An assessed, robots-blocking venue is the rare case.

**No per-user override.** `Scrapers::Agent` already has the right escape hatch —
`respect_robots = false`, set per-venue in code with a comment explaining why (the
Bad Bonn precedent). A venue whose `robots.txt` turns out to be a site-builder
default is a registry decision made once in a PR, not a checkbox on a capture form
that lets any contributor opt out of a call we recorded deliberately.

This decision depended on the fail-closed fix, **shipped in #97**: webrobots
fabricates a synthetic `Disallow: /` when the robots.txt fetch itself fails, so
without it the fallback message above would regularly have told a contributor "this
site says no" about a site that never said anything (Schüür 500s on `/robots.txt`
while serving its programme at 200). An unreachable robots.txt is now treated as
unknown and recorded on the `ScrapeResult`, so the adapter can trust that a refusal
means a real `Disallow`.

#### SSRF: validate before fetching, and on every hop

Fetching arbitrary user-supplied URLs from our server is an SSRF surface, and the
doc previously did not mention it. Decision 7 keeps it moderate — contributors are
admin-enabled, so the threat model is "a friend you approved pastes a link someone
sent them", not an anonymous attacker — but that is a reason to size the work, not
to skip it.

- **Scheme allowlist**: `http`/`https` only. Kills `file://`, `gopher://`, `ftp://`,
  `data:` in one line.
- **Reject non-global IPs** after resolving the host: `127.0.0.0/8`, `10/8`,
  `172.16/12`, `192.168/16`, `169.254/16`, `0.0.0.0/8`, `100.64/10`, `::1`,
  `fc00::/7`, `fe80::/10`. The one that matters most is `169.254.169.254`, the
  cloud metadata endpoint; on Render, private networking also makes internal
  service hostnames resolve to reachable private addresses. `Resolv` + `IPAddr`
  cover this — no new dependency.
- **Re-check every redirect hop.** The commonly missed step: an innocent public URL
  can `302` to `169.254.169.254`. Follow redirects manually, cap at 3–5, run the
  full check on each hop rather than only on what the user typed.
- **Timeouts, a response size cap, and a content-type allowlist** (`text/html`,
  plus image types if the adapter accepts poster URLs). These are the boring
  failure modes you actually hit.
- **Never echo the response body back.** Already satisfied: fetched text goes to
  the extractor and the verify screen shows extracted fields, not raw remote
  content.

Explicitly **not** doing the DNS-rebinding guard (resolve once, validate, connect
to that pinned IP with an explicit `Host:` header). It closes a real TOCTOU gap and
is the thorough version, but it is disproportionate to an admin-gated contributor
list — revisit if capture is ever opened up.

## Provider evaluation

### The question

Sending user images to a US provider sits badly with the privacy stance
([`project-product-ethos`]). Cost turned out to be irrelevant: at ~5 captures/day
every candidate lands between **$0.06 and $5.00 per month**, so the decision is
sovereignty and accuracy only. That also kills the cost case for self-hosting — a
GPU box costs more than $5/month in electricity alone, before ops.

### Method

`script/event_capture_bakeoff.rb` runs one identical prompt over six real samples,
repeated N times, and scores against `script/event_capture_bakeoff_truth.json`.
The samples were chosen to cover the failure modes, not the easy cases:

| Sample | What it tests |
|---|---|
| ZAR poster | brush script over a photograph |
| Bigote Verde | overlaid text, no address anywhere |
| Punto de Partida | the only sample stating a year; place is a street festival |
| Parterre | **two events on one poster**; no city; one date already past |
| WhatsApp text | venue identifiable **only** from a URL |
| WhatsApp screenshot-of-screenshot | cropped, **no date exists**, three acts |

The decisive metric is **fabrication rate**: how often a confident date appears for
the sample where no date is legible. A capture tool that invents dates is worse
than no capture tool.

Both WhatsApp screenshots are cropped and have sender names and phone numbers
painted over before upload. `--prep-only` writes exactly what would be sent and
opens it, making no network call — note that running with a bogus API key is *not*
equivalent, since the request body is uploaded before the 401 comes back.

### Results

Six runs each, identical prompt (`prompt_sha` is recorded in every session's
`manifest.json`, which is how we caught one early comparison mixing two prompts):

| Model | Fabricated dates | Wrong event count | Unstable fields | $/month | Latency |
|---|---|---|---|---|---|
| **Gemma 4 31B** (Infomaniak) | **0/6** | 1/36 | 3 | **$0.063** | 2.3s |
| Mistral Small 4 (Infomaniak) | 5/6 | 3/36 | 34 | $0.125 | 1.2s |

Mistral Small 4 also produced four spellings of "Marzili" (including the typo
`Quarterfest`), five of "parterre", and six variants of one URL — fatal for a field
used to match against a venue database.

**Decision: Gemma 4 31B on Infomaniak.** Swiss-hosted, an existing vendor
(registrar + DNS are already moving there), ~6 cents/month, and nothing leaves
Switzerland. No Anthropic/OpenAI account needed.

**Built** as `EventCapture` (`app/services/event_capture/`): `Prompt` carries the
tuned text and the strict JSON schema, `Infomaniak` makes the one call,
`Normalizer` + `YearResolver` decide every deterministic field, and `Extractor`
returns 0..n `Candidate`s or a failure. Credentials follow the `WebPushConfig` /
`MailConfig` pattern — `INFOMANIAK_API_TOKEN` + `INFOMANIAK_PRODUCT_ID` via env or
credentials, absent means inert rather than broken.

The entry point is `bin/rails "event_capture:extract[poster.jpg,...]"`, deliberately
ahead of any UI so the verify screen is written against a real contract. It takes
an image; text and URL inputs arrive with the adapters, which is also where image
downscaling belongs (the bake-off capped the long edge at 1568px with `sips`,
which is not a thing that exists on the deployed box).

**Downscaling is a latency decision, not a cost one** — worth stating before the
adapters are built, because the 1568px cap above reads like a cost measure and is
not. Gemma bills a *fixed* image cost, so across the bake-off its input was ~1294
tokens whatever the image: the 915x1568 sample came in at 1282, twelve tokens
*under* the 723x1568 one. Mistral does scale with pixels on the same pair (2496 →
2881), which is where the intuition comes from. The consequence is that the system
prompt, not the image, is ~95% of what a request costs — one extraction is ~1350 in
and 130–370 out, roughly $0.0005. So the only real cost lever is prompt length, and
shortening the prompt is exactly what the fabrication numbers say not to do.

The prompt is a **copy** of the bake-off script's, not a shared constant: that
script's recorded `prompt_sha` is what makes its sessions comparable, so it stays
frozen as the tuning rig. Two edits against it, both mandated above — `city`
became `locality`, and locality is defined as the tier below canton rather than
left to mean whatever "city" means.

### Two findings worth keeping

**Prompt tuning does not transfer between models.** The prompt revision that took
Gemma from 17% to 0% fabrication pushed Mistral from 40% to 83% on identical
inputs. Re-tune per model; never assume a prompt improvement is portable.

**Confidence scores are worthless here.** The first prompt asked for a
`confidence` field; it returned 0.90–1.00 on every output *including* an invented
venue ("Café Liebig", not present in the image) and three fabricated dates. The
field was removed. Do not gate anything on self-reported confidence.

### What made the difference

Requiring **verbatim citation** — every `date` and `place` must be accompanied by
`date_evidence` / `place_evidence` quoting the image text it was read from, or be
null. This is most of the gain, and it yields a free fabrication detector: a
populated value with a null evidence field is self-reported invention.

Naming the exact trap also mattered. The fabricated dates all came from the
WhatsApp "Saturday" day-separator, so the prompt now says explicitly that a
separator tells you when the *message* was sent, never when the event happens.

## Architecture principle: the model transcribes, code computes

Every deterministic thing the model was asked to do, it got wrong; every one moved
into code was then correct. This is the load-bearing lesson.

| Job | Model's record | Now |
|---|---|---|
| `is_past` | wrong every time | computed from `date` |
| Date format | returned `"Mi 19. August"`, `"2026-08-19T19:30:00"` | validated; datetimes salvaged, junk nulled |
| Time format | five formats: `20:00`, `20 Uhr`, `19:30h`, `19.30h`, `20:30 Uhr` | normalised to `HH:MM` |
| Canton | free text | checked against the 26, upcased |
| **Year resolution** | evidence read correctly 6/6, year wrong 2/6 | computed from the evidence |

Year resolution deserves its own note, because it is the clearest case. Given
`date_evidence` of `"Mi 19. August"`, the model transcribed it perfectly in all six
runs and still resolved it to **2025** in two of them — where 19 Aug 2025 is a
Tuesday and 19 Aug 2026 is a Wednesday, so "Mi" rules 2025 out.

It is tractable in code because the candidate set is tiny. A user photographing a
poster is looking at something happening soon, so the year is last, this, or next —
and a printed weekday picks exactly one of those, since a given day/month lands on
a given weekday only once every 5–6 years. Past dates are allowed but penalised:
a poster for 08.08 seen on 19.08 means the show was 11 days ago (stale poster), not
next year. All nine test cases resolve correctly.

A value failing validation is **nulled** and kept under `*_raw`, never trusted. A
null gets completed by a human in one tap; a malformed date silently corrupts the
feed. Shipped as `Candidate#raw` (keyed by field) plus `#issues` saying why — one
rule for every field, so the verify screen can show what the model claimed
alongside the null without a per-field special case.

The evidence rule earns one more thing there, read backwards: a **populated value
with a null evidence field is nulled too**, not merely flagged. A place the model
could not quote is self-reported invention (the bake-off's "Café Liebig" was not in
the image), and the citation requirement is only worth its prompt space if
something acts on it. The raw string survives, so nothing is lost — a human still
sees the claim, it just no longer arrives pre-accepted.

## Residual risk

With Gemma plus the code-side validators, one failure mode survives: roughly 1 in 6
runs collapsed the hardest sample (cropped screenshot-of-a-screenshot, three acts)
into a single event. That is not fixable in code — it is caught by a human on the
verify screen, which is the argument for that screen being a list you prune rather
than a single-record confirmation.

The evaluation is 36 samples from one afternoon on six images. Enough to choose a
provider; not enough to predict the long tail. The first fifty real captures will
teach more than more runs here.
