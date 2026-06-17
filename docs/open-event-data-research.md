# Open event data & aggregators — research (2026-06-17)

**Why this exists.** We hit a wall adding **Heitere Fahne** (Wabern) — a Vue SPA whose
start time + genre live only behind an undocumented `/ajax/` call. Rather than reverse a
private backend (rejected on ethics), we asked the broader question: *is there a sanctioned
feed / open dataset / aggregator that could replace our fragile per-venue scrapers and/or
unlock the JS-blocked venues?*

Six parallel research passes + firsthand verification. **TL;DR:**

| Rank | Source | License/terms | Time? | Genre? | Covers our venues | Verdict |
|---|---|---|---|---|---|---|
| 1 | **PETZI agenda** (petzi.ch) | public, robots-allowed; no open license | ✅ doors+show | ✅ tags | **16 of ours, live** | **BUILD IT** |
| 2 | **OLE / hinto.ch** | **CC-BY-SA (open)** | ✅ ISO-8601 | ✅ rich | only Dachstock | Promising, narrow |
| 3 | stadtkonzerte.ch | no grant (grey) | ❌ **no time** | patchy | broad | Enrichment only |
| 4 | Eventfrog API | **AGB forbids** modify/redisplay | ✅ | coarse | partial | Blocked by terms |
| — | Songkick / Bandsintown | terms exclude us; ClaudeBot-banned | mixed | ❌ | sparse | Dead end |
| — | bka.ch / Berner Kulturagenda | **explicit AI/bot opt-out + 403** | likely | likely | broadest | Dead end (ethics) |
| — | opendata.swiss / Bern OGD | open | — | — | **no events dataset** | Dead end |
| — | **Heitere Fahne** (the trigger) | — | only via private ajax | — | n/a | **Stays shelved** |

**Headline:** **PETZI is the find.** A single uniform, server-rendered, robots-allowed
source covering 16 of our venues with date + doors/show clock time + curated genre tags —
verified firsthand with a working POC (`script/petzi_poc.rb`). It can **consolidate ~16
bespoke scrapers** (including flaky beloved ones) and **add curated genres**, but it does
**not** unlock the JS-blocked venues (Heitere Fahne, ONO, …), which aren't in it.

---

## 1. PETZI agenda — BUILD IT  ⭐

PETZI is the Swiss federation of ~210 non-profit music clubs/festivals; it runs a shared
agenda + non-profit ticketing. **It is the ticketing backend behind many of our venues** —
which is why the data is centralized and clean.

**Access (all verified firsthand):**
- `robots.txt` (`User-agent: *`) disallows only `/admin/`, `/*-center/` — **`/events/`,
  `/agenda/`, `/locations/`, `sitemap.xml` are allowed.**
- `https://www.petzi.ch/en/sitemap.xml` enumerates **889 `/events/` URLs** — a complete,
  machine-readable index of every upcoming show. No pagination crawl needed.
- Detail URL: `…/events/{id}-{venue-slug}-{title-slug}/`. **Server-rendered HTML** (Alpine.js
  only drives menu chrome) — no JS execution required; Mechanize reads it directly.
- **No public API / RSS / JSON / iCal.** The route is: parse `sitemap.xml` → fetch detail
  pages. (84 distinct venues appear in the sitemap — also a *discovery* source for new venues.)
- Stay on `www.petzi.ch`; `tickets.petzi.ch` has a cert SAN mismatch (everything's on www anyway).

**Fields (verified on live pages):**
- `<title>` = `Title / DD.MM.YYYY / Venue - City / PETZI` (title + date + venue + city in one line)
- `<h1>` = clean title
- Body: `Doors open at: HH:MM` and `Event starts at: HH:MM` (both door **and** show time, labelled)
- `<a class="tag">` = curated genre/type tags (e.g. `Concert, Hip-Hop, Rap`; `Concert, Rock`)
- No structured **sold-out** field; cancellation would lean on our existing vanished-event sweep.
- List view lacks time+genre → must fetch each detail page (N+1; fine at venue scale, throttle politely).

**Verified live coverage of OUR venues** (events in the sitemap *right now*, not just "members"):

| Venue | Live events | | Venue | Live events |
|---|---|---|---|---|
| KIFF (Aarau) | 64 | | Sedel (Luzern) | 16 |
| Gaskessel (Bern) | 44 | | Nouveau Monde (Fribourg) | 11 |
| Docks (Lausanne) | 42 | | Helsinki (Zürich) | 10 |
| Kofmehl (Solothurn) | 36 | | Böröm | 6 |
| Dachstock (Bern) | 20 | | Café Kairo (Bern) | 3 |
| Fri-Son (Fribourg) | 18 | | Treibhaus / Le Singe / Zent | 2 each |
| Neubad (Luzern) | 17 | | | |
| ISC (Bern) | 16 | | **= 16 venues** | |

**NOT in PETZI** (keep their bespoke scrapers): Bad Bonn, Rote Fabrik, Südpol, Kaserne,
Dynamo, Mahogany Hall, Turnhalle, Schüür, Bierhübeli, Volkshaus, Dampfzentrale, Sous Soul,
Rössli, Sägegasse, Bar 59, Mühle Hunziken. **And none of the JS-blocked targets** (Heitere
Fahne, ONO, Café Hueber, Marians, PROZESS, Café du Commerce, Mokka) are in it.

> ⚠️ **Important correction to the initial research:** a subagent reported "15/19 venues are
> PETZI *members*." Membership ≠ live agenda coverage. The numbers above are the *actual*
> sitemap contents, which is what matters. Bad Bonn & Rote Fabrik are members but currently
> push **zero** events to the PETZI agenda.

**POC result.** `script/petzi_poc.rb` (sitemap → filter → detail-page extract) ran clean
against 8 venues. Sample:

```
Kofmehl (Solothurn)
  title : Malevolence    date: 17.06.2026    venue: Kulturfabrik Kofmehl - Solothurn
  doors : 18:00          show: 18:45         genres: Concert, Rock
Gaskessel (Bern)
  title : Free Quenzy Bash    date: 26.06.2026    doors: 21:00    show: 21:00
  genres: Concert, Hip-Hop, Rap
ISC (Bern)
  title : Anda Morts    date: 10.09.2026    doors: 20:00    genres: Club, Concert, Indie, Punk
```

**Pros:** one robust source replaces ~16 fragile scrapers; curated genres for free; reliable
ISO-derived times; sitemap = no pagination fragility; mission-aligned non-profit; also a
discovery source for ~68 other Swiss venues.
**Cons:** no open license (rests on "public + robots-allowed" — recommend a courtesy email to
`support@petzi.ch`); N+1 detail fetches; no sold-out field; doesn't unlock JS-blocked venues;
some events miss show-time or genre tags (per-event variance, ~handful in the POC).

---

## 2. OLE / hinto.ch — open, but Bern-only & narrow

**Open Linked Event Data**, CC-BY-SA, via hinto.ch. The *cleanest* license of all and trivial
to consume (XML pull, no auth, ISO-8601 timestamps, genre `categories`).

- Registry: `https://www.hinto.ch/oleexport` → ~20 publisher feeds. Each feed is plain XML.
- **Coverage of ours: only Dachstock** (`https://api.dachstock.ch/wp-json/ds/v1/hinto` — live,
  fresh 2026→2027, full timestamps, genres like "Dream Pop"). The rest of the network is
  Bern churches / jazz / cinema / civic culture.
- License obligation: attribution + share-alike, and publicly disclose which OLE sources you
  consume (a small "data sources" page satisfies it).

**Use:** swap the Dachstock scraper for its OLE feed (more robust + structured genres), and
auto-watch the registry for future indie publishers. Not a fleet replacement.

---

## 3. stadtkonzerte.ch — enrichment only

Broad multi-city aggregator; `/locations/<slug>` pages are server-rendered (scrapable). Covers
almost all our Bern venues **and** several JS-blocked ones (Heitere Fahne, ONO, Marians, Café
Hueber, PROZESS). **But shows no clock time** (date+title+price only) and points out to venue
sites for the time — so it can't be a primary source. Possible value: a *cross-check / discovery*
layer, or a last-resort date-only listing. No reuse grant (legal grey).

---

## 4. Eventfrog API — technically great, blocked by terms

Documented public REST/JSON API (`api.eventfrog.net/api/v1`), free key, Switzerland-wide,
great filters, ISO times, `cancelled` flag, coarse categories. Covers some of ours (Kofmehl,
Café Kairo, Rote Fabrik, Heitere Fahne…) but misses the Fribourg indie cluster.

**Blocker = AGB §17:** forbids content **modification** ("inhaltliche Veränderungen" — collides
head-on with our genre-normalization / dismiss / re-bucket pipeline), forbids **passing data to
third parties** (a public reader is grey), and limits use to event *announcement*. Not open (no
CC-0). Would require a direct cooperation agreement. **Park it** unless we pursue a formal deal.

---

## 5. Dead ends (recorded so we don't re-investigate)

- **Songkick** — API is paid-partner-only, explicitly refuses hobby use; HTML venue pages
  ClaudeBot-banned, no time/genre, sparse (artist-self-report). Sold to an AI firm Nov 2025.
- **Bandsintown** — API is artist-only (no venue endpoint); Data Terms restrict use to
  "artists/their reps," prohibit scraping & transfer to similar services. Excludes us.
- **bka.ch / Berner Kulturagenda** (kulturagenda.be) — broadest Bern catalogue, but `robots.txt`
  is an explicit **AI/bot opt-out** (`Disallow: /` for ClaudeBot/GPTBot/CCBot…, `ai-train=no`)
  and returns **403**. Conflicts with our ethics — don't scrape; the right path is to *ask the
  Verein* for data access.
- **opendata.swiss / Stadt Bern OGD / Kanton Bern** — open licenses, but **no cultural-events
  dataset** for indie clubs (only venue locations, stats, geodata). Re-check periodically.
- **gigle.ch** — appears defunct (connection refused; last archive ~2020). (`gigs.ch` is a
  different live site — not yet evaluated.)

---

## 6. Heitere Fahne — the original trigger — STAYS SHELVED

Public, server-rendered data = the listing's `<event-list :initial-data>` JSON only: title,
subtitle, date (but **time-less `00:00:00`**), image, id. Detail URLs are deterministic
(`/events/{id}/{DD-MM-YYYY}/{slug}`) but **client-side only — start time + category come from a
`/ajax/` XHR** (undocumented backend → rejected). No JSON-LD, no `.ics`/RSS/sitemap feed. Not
in PETZI or OLE; on stadtkonzerte but without a time. **No clean path to time+genre exists.**
Backlog note updated.

---

## Recommendation & next steps

1. **Build a `Scrapers::Petzi`** (template-method Agent + golden fixtures): sitemap →
   filter to our 16 venues → detail-page extract (title, date, doors/show, venue/city, genre
   tags). Biggest single win: consolidates ~16 scrapers and adds curated genres.
   - **Open decision (yours):** *replace* the 16 existing per-venue scrapers, or run PETZI
     *alongside* them and **dedup**? Replacing is cleaner but loses any venue-specific fields
     the bespoke scrapers extract; alongside needs a dedup key (venue + date + fuzzy title).
   - Genre handling: PETZI tags are curated-ish but third-party → lean **consumption
     (match-only)** at first, like docks/mahogany.
   - Courtesy: email `support@petzi.ch` to sanction a polite daily crawl (no open license).
2. **Swap Dachstock → its OLE feed** (CC-BY-SA, structured genres, robust). Add an OLE
   "data sources" disclosure page to satisfy the license. Watch the registry for new publishers.
3. **Park Eventfrog** behind a possible cooperation agreement; **drop** Songkick/Bandsintown/
   bka/open-data portals.
4. **Heitere Fahne, ONO, Café Hueber, Marians, PROZESS** — no sanctioned path today; revisit if
   they ever join PETZI or publish a feed. stadtkonzerte could give date-only stubs if ever wanted.

*POC lives at `script/petzi_poc.rb` (standalone, persists nothing). See
[[project-open-event-data-avenues]] memory for the condensed version.*
