# User event capture — design decisions and model evaluation

> Status: **decided, not yet built** (2026-08-19). Supersedes the framing in
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
   per-candidate accept/edit/drop. Single capture is just N=1. Extraction must be
   async — you cannot hold a request open for eight vision calls.

2. **The unit is 0..n events per input, not one.** A poster can advertise two
   concerts; a festival timetable three acts. Both occur in the sample set.

3. **Place splits into two kinds**, and the venue registry is *not* extended
   automatically:
   - `Venue` (`config/venues.yml`) keeps its current meaning — **venues we source
     from**. Still closed, still PR-approved. It cannot be written at runtime
     anyway: it is a code file, `main` is PR-gated, deploys are tag-gated, and
     Render's filesystem is ephemeral.
   - Captured events get a DB-backed place with a type: `venue` or `ad_hoc`
     (Marzili Quartierfest, "Konzert im Kocherpark").
   - `Location.type_for` must consult both. Today it classifies anything unknown
     as a **city** (`app/models/location.rb`), so a captured "ZAR" would silently
     appear as a city in the WHERE tree. That is the concrete bug to fix.
   - A captured real venue becomes a **`VenueLead`** — the existing discovery
     inbox at `/admin/venue_leads`, which already ranks by `event_count`. Capture
     three events at ZAR and it rises in the inbox; that is the signal to write a
     scraper and add the YAML row by PR. Auto-add is replaced by auto-*nominate*.

4. **Ad-hoc places are filterable but not in the WHERE tree.** No work needed:
   `Filter#location_list=` passes free names straight to `locations_name_in`
   without validating against the taxonomy.

5. **Place-name normalisation uses the genre fingerprint pattern** — the stored
   generated column that folds case, spacing, punctuation and umlauts, plus
   `canonical_id` for alias-merge. Its reach is limited: it collapses
   `MARZILI`/`Marzili` but not `Quartierfest`/`Quarterfest` or
   `Schützenmatt`/`Schützenmatte`. **The real defence is match-at-entry** — the
   verify UI offers existing places that fingerprint-near the extracted name and
   the user taps one. Fingerprint + admin merge is the safety net, not the plan.

6. **Canton is required; city is optional.** A one-off concert in a forest between
   Bern and Luzern has no city but is unambiguously in some canton, and canton is
   the top of the WHERE tree — enough for the event to be findable, which is the
   only reason to require anything. Canton is a closed list (26, realistically
   ~6); city is free text with suggestions from existing tags. Same
   closed-where-finite / open-where-not rule as venues vs genres.

7. **Captured events go live immediately**, and a report **quarantines the event,
   not the person**. Contributors are admin-enabled, so the abuse surface is
   ~zero; the realistic report is "this date is wrong" or "this got cancelled".
   Auto-suspending a user on one report is a griefing vector and punitive
   machinery for people you personally approved. Reports from signed-in users
   only. Framing is *"stimmt etwas nicht?"*, not an abuse report.

8. **Captured events live outside the scraper's re-derivation domain.**
   `Scrapers::Agent#build_event` re-derives every field from source nightly and
   `find_or_initialize_by(url:)` resurrects deleted rows. A captured event has no
   source to re-derive from, and `events.url` is `NOT NULL` + unique while a
   poster has no URL. Use the existing `data_source` column as the seam. When a
   venue later gains a scraper, the duplicate is handled by `canonical_event_id`.

9. **No image is stored.** Processed then discarded, consistent with the rejected
   `image` field (see [`richer-fields-proposal.md`](richer-fields-proposal.md)).
   The verify screen doubles as the PII checkpoint: the human sees, and edits,
   exactly what will be persisted.

### Still open

- Whether the URL adapter's one-off fetch should honour `robots.txt` the way the
  nightly scrapers do. It is user-initiated rather than a crawl, which is
  arguably a different act.
- Exact shape of the place model (new table vs. extending something existing).

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
feed.

## Residual risk

With Gemma plus the code-side validators, one failure mode survives: roughly 1 in 6
runs collapsed the hardest sample (cropped screenshot-of-a-screenshot, three acts)
into a single event. That is not fixable in code — it is caught by a human on the
verify screen, which is the argument for that screen being a list you prune rather
than a single-record confirmation.

The evaluation is 36 samples from one afternoon on six images. Enough to choose a
provider; not enough to predict the long tail. The first fifty real captures will
teach more than more runs here.
