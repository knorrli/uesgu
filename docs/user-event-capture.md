# User-contributed event capture — idea note (2026-06-23)

> Status: **maybe-later / idea preservation.** Not planned, not scoped for
> delivery — a brain-dump so the ideas aren't lost. Linked from `BACKLOG.md`
> ("Maybe-later"). Two specific prompts (a WhatsApp concert-tip group; snapping a
> photo of a street poster) turned out to be the **same feature**; this note
> records the framing and a rough poster-capture pipeline.

## The problem this addresses

üsgu's core promise is "you won't miss a show." The honest version is narrower:
*you won't miss a show **at a venue we scrape**.* Coverage is bounded by the
supply side — every scraper is us trying to enumerate one more venue. Aggregators
are largely exhausted (see `docs/open-event-data-research.md`), and the long tail
(house shows, one-offs, tiny rooms, grapevine tips) is unreachable by scraping in
principle.

## The unifying frame

Two long-standing ideas — the original motivations for the project — are the
**same primitive**: *human-mediated capture of an event from unstructured input.*

- **WhatsApp group.** A group where people post upcoming concerts in/around Bern —
  exactly the target content. Anti-AI, privacy-oriented members; **cannot** be
  mined automatically.
- **Street poster.** On a walk you see a poster/flyer. Instead of memorising it or
  hunting online later, snap a photo and a "magic box" leads you to the event.

Strip away the modality (text vs. image) and both are one funnel:

> A user **voluntarily** hands üsgu an unstructured thing they encountered →
> üsgu extracts the event facts → dedup against what we already have →
> it fills a coverage gap (or links an existing event).

This attacks coverage from the **demand side** instead of the supply side.
Instead of üsgu enumerating every venue, people surface the events they
personally bump into; the union of everyone's encounters reaches the long tail no
scraper ever will. That long tail is *exactly* the "shows you miss" category that
started the project.

Most of the back-end already exists: `canonical_event_id` dedup, admin manual
event tooling, and the `overridden_fields` manual-override machinery. The missing
piece is an **ingestion funnel**, not a data model.

## Idea 1 — WhatsApp tips: the ethos is the whole design constraint

The bright line is **what** you capture, not whether you capture:

- **Across the line — do NOT build:** anything that *monitors the group* — a bot
  in the chat, a "connect WhatsApp" flow, bulk message ingestion, storing
  who-said-what. That is the AI-scraping-our-group thing those members (rightly)
  reject. Don't build it; don't even ship a slick forward-to-üsgu deep link if it
  would *feel*, socially, like the group has been wired up to a machine.
- **On the safe side — do:** a member, on their own initiative, captures *one
  event* the same way they'd jot it in their own calendar. The human is the
  bridge. üsgu never touches the group.

To keep it defensible, capture the **event** and discard the **provenance**:

- Extract artist / venue / date / time → store the *event*, not the verbatim
  message, not the poster's name, not "from WhatsApp."
- The recorded thing is a public happening, not a person's words. That's the
  ethical gap between "I added the show to a shared list" (normal human behaviour)
  and "we archived your group" (creepy).

Nice property: done right this *strengthens* the group rather than competing —
the tips still happen in WhatsApp; üsgu just means nobody has to mentally hold a
date for three weeks. The AI-allergy irony (the feature serving anti-AI people is
LLM-powered) is fine **because** it runs only on the submitter's own voluntary
input, never on the group — but the framing ("I captured an event," not "AI read
our chat") does real work and must drive the UX copy.

**Open question:** WhatsApp-sourced events private-to-submitter by default, or
shared into the public feed? Lean **private-first**, with explicit opt-in to
share. Private-first is the ethos-safe default (üsgu as a personal capture tool)
and also the spam-safe default.

## Idea 2 — snap a poster: the flagship version of the same thing

The most *üsgu* feature imaginable, and vision models make it genuinely good now:
on a walk, see a poster, snap → "we'll watch this for you / here's the event."
The original intent in its purest form. Same extract→dedup pipeline as Idea 1,
with **zero social-trust baggage** — which is why it should go first.

### Rough pipeline (poster capture)

1. **Input.** User uploads/snaps a photo (PWA camera input). No image is stored
   long-term — processed then discarded, consistent with the rejected
   `image` field decision (privacy: no event imagery on our servers).
2. **Vision extraction.** One multimodal call → structured
   `{ artist/title, venue, date, time, genre?, confidence }`. Treat low
   confidence and missing date/time as first-class (posters are ambiguous).
3. **Dedup — the make-or-break.** Match the extracted event against existing
   events via the `canonical_event_id` machinery (venue + date + fuzzy title).
   Two outcomes:
   - **Match:** "We already track this — here it is" → one tap to follow.
     Delightful, and reassures that üsgu is comprehensive.
   - **No match:** mint a **provisional** event from the poster alone → additive
     coverage. For a venue we *do* scrape, it reconciles on the next scrape run;
     for a venue we *don't*, it's pure new coverage (the long-tail win).
4. **Provisional state + confirmation.** A "needs confirmation" status (cf. the
   admin manual-override / curation flow). Provisional events must **not** pollute
   other users' feeds until verified — guards against hallucinated dates and
   stale/past posters.
5. **Follow.** Once accepted, it's an event like any other — trackable by the
   existing follow/notify machinery, which is the whole point.

## Risks / hard parts (be honest)

- **Dedup is make-or-break**, not the LLM call. Bad dedup → duplicate sludge.
  Existing `canonical_event_id` work is why this is feasible, but it's the real
  engineering cost.
- **Hallucination / stale posters.** Vision models confidently misread dates; a
  snapped poster may be for a past show. Hence provisional + confirmation, and no
  leakage into shared feeds before verification.
- **Abuse / spam** the moment anything is publicly shared → argues again for
  private-first, share-as-opt-in.
- **AI cost** per capture (vision call). Fine for personal-tool volumes; worth
  noting.

## Recommendation (if/when revisited)

Build **one "capture an event" funnel** with two input adapters —
**paste-text** and **snap-photo** — feeding a shared
*extract → dedup → provisional-event* path. One feature, not two projects.

Sequencing: **start with the poster/photo path.** More magical demo, zero
social-trust baggage, exercises the exact extract+dedup pipeline, proves the
primitive. Once solid, the WhatsApp case is *just the text adapter* into the same
machine — no new infrastructure, only the ethos framing and the private-by-default
policy.
