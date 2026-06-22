# Richer event fields — coverage audit + schema proposal

> Status: **decision-ready proposal**. No migration has been run and no scraper
> changed. This unblocks the `BACKLOG.md` item *"Capture richer fields some
> sources expose but we drop"*, which is blocked on a schema decision. Pick the
> column set (and the image-privacy stance), and the wiring is mechanical.

## TL;DR

- **No `price` / `lineup` / `description` / `image` column exists today.** The
  only user-facing content columns are `title` and `subtitle`. So *every*
  scraper that sees these fields necessarily drops them — there is no
  `build_event` hook to assign them to. The work is genuinely schema-blocked.
- The two backlog-flagged sources are **confirmed**: Bad Bonn exposes a price,
  bar59 exposes lineup + description + image.
- Beyond them, **OLE** and **PETZI** confirmably read-and-drop a description (and
  OLE an image); **Mahogany Hall** has a price in markup. A second wave of
  WordPress/ACF/JSON feeds (Bierhuebeli, Suedpol, Rote Fabrik, Le Singe) and the
  click-into-detail HTML scrapers almost certainly carry image/description too —
  but those need a per-fixture check before wiring (listed as *probable*).
- **Recommendation:** add four freeform columns — `price:string`,
  `lineup:text`, `description:text`, `image_url:string` — preserving source text
  verbatim (match-not-rewrite, consistent with how we treat genre tokens). The
  one genuine decision beyond "yes/no" is **whether we hotlink venue images**
  (privacy implications below).

## 1. Current schema (verified against `db/schema.rb:37-62`)

`events` columns relevant here: `title` (not null), `subtitle`, `start_date`,
`start_time`, `url` (unique upsert key), plus housekeeping (`hidden`,
`cancelled_at`, `dismissed_at`, `overridden_fields` jsonb, `data_source`,
`canonical_event_id`, …). Genres and locations are **not** columns — they are
`acts-as-taggable-on` taggings.

**Confirmed: none of price / lineup / description / image exist.** Capturing any
of them requires a migration first.

## 2. Scraper architecture (so the wiring cost is clear)

All scrapers: `app/services/scrapers/`, base `Scrapers::Agent < Mechanize`
(`agent.rb`). Template method `process_events` (agent.rb:148-208) →
`build_event` (agent.rb:237-272) assigns persisted fields via overridable hooks:
`event_start_time`, `event_title`, `event_subtitle`, `event_genres`,
`event_locations`, plus cancelled/rescheduled flags.

There is **no hook** for price/lineup/description/image. Adding the feature =
(a) the migration, (b) new `build_event` assignments + default hooks in the base
returning `nil`, (c) per-scraper hook overrides where the data exists, (d)
plumb the new fields through `overridden_fields` manual-edit locks and the admin
edit form, (e) render them in the event view.

`field_gaps` (agent.rb:111-122) only ever tracks the coverage-matrix fields
(`:time`, `:subtitle`, `:genres`) — it does **not** apply to the new fields, so
no `field_gaps` changes are needed. The coverage matrix could later grow columns
for the new fields, but that's optional polish, not part of the unblock.

## 3. Confirmed dropped-field inventory

P=price · L=lineup/artists · D=description · I=image.

| Scraper | File:line | Source field/selector | → | Confidence |
|---|---|---|---|---|
| **bar59** | `bar59.rb:88-98` (`flatten`) | Firestore `artists` | L | confirmed (fixture) |
| **bar59** | `bar59.rb:88-98` | Firestore `htmlText` | D | confirmed |
| **bar59** | `bar59.rb:88-98` | Firestore `picture` | I | confirmed |
| **Bad Bonn** | `bad_bonn.rb:50-52` (node already in hand) | `article[data-date]` `data-price` | P | confirmed (`data-price="25"`) |
| **OLE** (Dachstock, Bewegungsmelder) | `ole.rb:406-411` | `<description>` (currently used only as a boolean subtitle gate) | D | confirmed read-but-dropped |
| **OLE** | `ole.rb:28-29` | `<image>` (ignored by design) | I | confirmed |
| **PETZI** | `petzi.rb:83-86` | `<p class="text_block">` (page already fetched) | D (+L in prose) | confirmed |
| **Mahogany Hall** | `mahogany_hall.rb:38` (code comment) | row price field | P | noted in code |

bar59 is the single richest source and is the easiest first wire (the data is
already a parsed hash in `flatten` — just stop dropping it):

```ruby
# bar59.rb:88-98 — today's flatten drops artists / htmlText / picture / location
def flatten(doc)
  fields = doc['fields'] || {}
  {
    'id'        => doc['name'].to_s.split('/').last,
    'title'     => fields.dig('title', 'stringValue'),
    'date'      => fields.dig('date', 'timestampValue'),
    'startTime' => fields.dig('startTime', 'stringValue'),
    'genre'     => fields.dig('genre', 'stringValue'),
    'isActive'  => fields.dig('isActive', 'booleanValue')
    # + 'artists' (L) / 'htmlText' (D) / 'picture' (I) sit right here, unread
  }
end
```

### Probable (detail page already fetched; needs a fixture check before wiring)

Docks, Kofmehl, Boeroem, Sedel, FriSon, Schüür — click into a detail page, so the
full DOM (likely price/description/image) is already in hand. WordPress/ACF/
JSON:API feeds — Bierhuebeli, Suedpol, Rote Fabrik (`rf_event`), Le Singe,
Dynamo — almost certainly carry featured-media + body fields. The backlog's
"re-run the audit across the rest" step lands here, and is cheap once columns
exist: each is a quick fixture inspection + a hook override.

## 4. Schema proposal

Recommended migration — four nullable columns, all freeform (preserve source
text, no parsing/normalisation), consistent with the project's match-not-rewrite
treatment of genre tokens:

```ruby
class AddRicherFieldsToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :price,       :string  # raw source text: "25.–", "CHF 20/25", "frei"
    add_column :events, :lineup,      :text    # support/artists as the source gives it
    add_column :events, :description, :text    # venue blurb; sanitise HTML on render, store raw
    add_column :events, :image_url,   :string  # see §5 — privacy decision required
  end
end
```

Design notes / rationale:

- **`price` as a string, not a number.** Source formats are wildly inconsistent
  ("25.–", "CHF 20/25 (AK/VVK)", "Kollekte", "frei", ranges). Parsing them loses
  information and invites bugs; storing the raw token and rendering it as-is
  matches how we already treat genres. A structured price model is over-
  engineering for a personal tool.
- **`description` stored raw, sanitised on render.** bar59's `htmlText` and
  PETZI's blurb are HTML. Store verbatim; sanitise + truncate in the view (Rails
  `sanitize`). Don't strip at ingest — keeps the door open for richer rendering.
- **`lineup` as text** — some sources give an array (bar59 `artists`), some bury
  support in prose (PETZI). Join arrays to newline-separated text at ingest; a
  separate join table is overkill.
- **These must respect `overridden_fields`.** Each new field needs to be lockable
  by the admin manual-override mechanism (see `project-admin-manual-overrides`)
  so a hand-edit survives re-scrape, exactly like title/subtitle today.

## 5. The one real decision: image privacy

This is the only choice that isn't a rubber-stamp, and it touches the product's
**privacy-first ethos** (`project-product-ethos`):

- **`image_url` = hotlink the venue's image.** Cheap, no storage. But the
  user's browser fetches the image directly from the venue's server on every
  feed render — leaking the user's IP, user-agent, and "is looking at this event
  right now" to every venue + their CDNs/trackers. For a privacy-first site for
  friends, that quietly undoes a core promise.
- **Proxy/cache images ourselves** (download at scrape time, re-serve from our
  domain). Preserves privacy, costs storage + a fetch pipeline + cache-busting +
  broken-image handling. Heavier, but honest.
- **Skip images entirely**, ship only price/lineup/description (all text, no
  privacy leak). Smallest, safest, still captures the richest *text* fields.

**Recommendation:** ship `price` + `lineup` + `description` now (no privacy
cost, immediate value), and treat `image_url` as a separate follow-up gated on
the proxy-vs-hotlink-vs-skip call. If you want images now, I'd lean **proxy**
over hotlink to keep the privacy promise intact — but that's yours to decide.

## 6. Open decisions for you (answer these and I'll wire it)

1. **Ship the migration?** Recommended columns: `price:string`, `lineup:text`,
   `description:text` (+ `image_url:string` pending #2).
2. **Images:** hotlink / proxy-and-cache / skip-for-now? (Recommend skip-for-now
   or proxy.)
3. **Coverage matrix:** extend `/admin/scraper_coverage` with columns for the new
   fields, or leave the matrix as time/subtitle/genres? (Optional; not blocking.)
4. **Rollout order:** wire the four confirmed sources first (bar59, Bad Bonn,
   OLE, PETZI, Mahogany Hall), then sweep the *probable* list per-fixture? (Yes,
   recommend.)
