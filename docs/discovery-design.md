# Source/venue discoverability — design

How we find venues/feeds we don't yet consume, without re-evaluating ones we've
already judged. **Read-once rationale.** The edit-time field reference lives in
the header of `config/venue_ledger.yml`; the rules below are enforced by
`test/services/scrapers/ledger_drift_test.rb`. This doc is the *why*.

## The problem

Finding "what venues/feeds exist that we don't already consume" is manual today.
Three upstream indices enumerate far more venues than we track:

- **OLE registry** — `hinto.ch/oleexport`, a human-readable HTML list of ~20
  per-venue OLE endpoint URLs. Non-authoritative: a venue can expose an OLE feed
  without being listed, and the list grows.
- **Hinto ALL** — the `id/all` OLE feed enumerates ~46 venues via `<location>`
  blocks, even venues without their own listed endpoint. Richer than the registry.
- **PETZI sitemap** — `petzi.ch/.../sitemap.xml` (~889 events). Each event URL
  encodes its venue in the slug (`/events/{id}-{slug}-{title}`). We track 14
  slugs (`Petzi::VENUES`); other venues are discoverable from distinct slugs.

## The operation: `Delta = Universe − Known`

- **Universe** = the union of venue identities the upstream indices expose.
- **Known** = everything we've already decided on: consume ∪ defer ∪ reject.
- **Delta** = the unknowns to surface for human triage.

The set-difference is trivial. The two hard parts are **(a) what counts as a
venue identity** across upstreams that key differently, and **(b) where "Known"
lives** so the subtraction is reliable and never re-flags a past decision.

## Identity: the canonical key is the venue's domain (eTLD+1)

A venue wears a different key in each upstream — a PETZI slug (`dachstock`), an
OLE feed host (`api.dachstock.ch`), a Hinto `<location>` name. The one stable,
unique identity across all of them is the **venue's own website domain**,
normalized to its registrable form (eTLD+1): `api.dachstock.ch`,
`www.dachstock.ch`, `https://dachstock.ch/events` all collapse to `dachstock.ch`.

This is the venue-level analogue of the event `canonical_event_id` dedup and the
genre alias-match-not-rewrite pattern: one canonical key, with per-upstream raw
keys recorded as **aliases** that resolve to it.

**The domain is the key, but it is not always auto-extractable from the
upstream** — and that gap *is* the manual triage step:

| Upstream            | What it hands you                 | Domain auto-derivable? |
| ------------------- | --------------------------------- | ---------------------- |
| OLE feed / scraper  | the venue's own URL               | **Yes** — strip to eTLD+1 |
| PETZI sitemap       | a slug on `petzi.ch`              | **No** — host is `petzi.ch` for all venues |
| Hinto ALL           | a `<location>` name/address       | **No** — name only |

So aggregator-hosted upstreams give a slug/name that a human resolves to the
canonical domain **once**; that resolution is recorded as an alias and the key
is subtracted forever after. The same gap bites single-venue scrapers whose feed
lives on a SaaS backend (`Bar 59` → `firestore.googleapis.com`, `Dynamo` →
`dynamo.nodehive.app`): the URL host isn't the venue, so the scraper declares its
canonical domain explicitly (`venue_domains` override), and the drift test
catches any scraper that forgets to.

Edge: a roving promoter/series (BeJazz) has no fixed venue — its domain keys a
*source*, not a place. That's fine; the key is still unique. And a single domain
that hosts two halls collapses them into one row (usually what we want). Le Singe
has no own site; its operator/feed host `kartellculturel.ch` is the honest key.

## Where "Known" lives: a repo-side YAML ledger

`config/venue_ledger.yml` is the authoritative record of every venue-identity
we've decided on. One entry per canonical domain.

We chose **repo YAML over a DB table** because *enabling a source is already a
code change* (a new `Ole::SOURCES` entry → generated subclass, or a new
`Petzi::VENUES`/bespoke scraper). Keeping the decision in the same place as the
consequence means it's code-reviewed, versioned, diffs cleanly in PRs, and
travels with deploys — and matches the product ethos (a human-reviewed change,
not a button that mutates production). Reject/defer reasons that would otherwise
live as freeform prose become keyed, queryable entries — which is what makes
re-flagging suppressible.

Cost of YAML: it must not drift from the constants/scrapers that actually drive
scraping. That risk is eliminated by the drift test (below), which fails the
build on any divergence.

### Entry schema

```yaml
- domain: dachstock.ch            # canonical eTLD+1 — primary key
  name: Dachstock                 # display label
  disposition: consume            # consume | defer | reject
  checked: 2026-06-21             # date last evaluated — drives re-check staleness
  aliases:                        # per-upstream raw keys that resolve to this domain
    petzi: [dachstock]            # PETZI slug(s)
    ole:   [api.dachstock.ch]     # OLE feed host(s)
    hinto: ["Dachstock Reitschule"]  # Hinto <location> name(s)
  # `reason` required for defer/reject, forbidden on consume
```

- **`domain`** — eTLD+1, normalized. The one true key. One row per domain.
- **`disposition`** — `consume` (actively scraped; MUST be backed by a live
  scraper), `defer` (wanted but blocked now; not scraped), `reject` (evaluated,
  not wanted).
- **`reason`** — required iff defer/reject, forbidden on consume. Vocabulary
  lives in the `reasons:` block of the ledger (code reads it).
- **`checked`** — date last evaluated; the staleness clock for re-check.
- **`aliases`** — the resolvers. Any upstream raw key matching an alias is
  subtracted, so triage "sticks". A venue consumed via two sources (Dachstock via
  PETZI *and* OLE) is one row with two aliases — the key dissolves the whole
  "duplicate-of-existing" category.

Deliberately **absent**: no `scraper:` field (which class consumes a domain is
derived live from the registry — naming it here would be a third source of truth
to drift), and no `duplicate` reason (domain-keying makes it impossible to express).

### Reason vocabulary (stored as data, not prose)

The `reasons:` map in the ledger carries each code's human explanation **and** a
`revisitable` flag. Code reads the same map: the drift test validates
`reason ∈ reasons`, and the re-check staleness logic reads `revisitable` from it
— so behaviour can never disagree with the documented meaning (same principle as
the living styleguide).

| code        | meaning                                   | revisitable |
| ----------- | ----------------------------------------- | ----------- |
| `robots`    | robots.txt disallows the feed/pages       | yes |
| `js_only`   | JS-rendered, no machine-readable data      | yes |
| `no_date`   | listings exist but no scrapeable date/time | yes |
| `inactive`  | feed/site exists but is unmaintained/stale | yes |
| `non_music` | not a music venue (cinema, cabaret, …)     | **no** |
| `promoter`  | roving series/promoter, no fixed venue     | **no** |

Revisitable reasons re-surface for re-check once `checked` is older than the
staleness window (default **6 months**); permanent reasons stay buried.

## Drift detection (the CI test)

The "consume" set is **not** just `Ole::SOURCES` + `Petzi::VENUES` — it's the
entire `Scrapers::All.scrapers` registry, including every direct-venue scraper.
Each scraper exposes the domains it covers via `venue_domains` (single-venue:
`[eTLD+1 of its url]`, overridable for SaaS-hosted feeds; PETZI: its 14 venue
domains). The unit of reconciliation is the **venue-domain**, because one scraper
can cover many (PETZI → 14) and one domain can be covered by many (Dachstock via
bespoke + OLE + PETZI).

`test/services/scrapers/ledger_drift_test.rb` enforces, with explanatory failure
messages (a failure teaches the rule at the moment it's violated):

1. **No orphan consume row** — `LedgerConsume − RegistryDomains = ∅`. A consume
   row with no scraper claiming it = stale/renamed/typo'd entry.
2. **No unrecorded scraper** — `RegistryDomains − LedgerConsume = ∅`. A scraper
   covering a domain with no consume row = scraper merged without a ledger entry.
   *(This disciplines direct-venue scrapers.)*
3. **Reason well-formedness** — defer/reject rows carry a valid `reason`; consume
   rows carry none.
4. **Domain normalization** — every `domain` equals its own eTLD+1 (no
   scheme/subdomain/path).
5. **Alias uniqueness** — no single alias maps to two domains.

Rules 1+2 are load-bearing and make `SOURCES`/`VENUES` coverage *transitive*: if
`Petzi.venue_domains` derives from `Petzi::DOMAINS`, rule 2 forces every PETZI
venue to have a consume row — no separate "check VENUES" assertion needed. (A
parity assertion keeps `Petzi::VENUES` and `Petzi::DOMAINS` key sets aligned.)

## Discovery diff (the report)

A periodic, **read-only** rake (`discovery:report`, weekly via the Render cron),
stable-sorted so re-runs are quiet:

1. **Fetch + extract raw keys** per upstream: OLE registry HTML → feed URLs;
   Hinto ALL → `<location>` blocks; PETZI sitemap → distinct event slugs.
2. **Resolve each raw key → domain**: OLE URL → eTLD+1 (automatic); PETZI slug /
   Hinto name → look up in `aliases` (hit → known domain, miss → unresolved).
3. **Partition**:
   - **Known** (resolved domain has any ledger row) → suppress. *Exception:*
     defer/reject with a `revisitable` reason and stale `checked` → **Re-check**.
   - **New, domain-resolved** (e.g. a fresh OLE endpoint whose eTLD+1 isn't in the
     ledger) → **New candidate**.
   - **New, unresolved** (PETZI slug / Hinto name with no alias) → **New candidate
     needing identification** — the human maps slug→domain (the irreducible hop).
4. **Emit** three sections: New candidates (with a cheap music/non-music
   auto-classify guess to order triage), Re-check (stale revisitables), and a
   Drift summary (same reconciliation as the test).

The **only write path** is a human appending/editing a ledger row in a PR
(disposition + reason + `checked` + the alias they resolved). Next run, that key
is permanently subtracted.

## Read-only triage, never auto-enable

Discovery's job ends at "here are N new candidate venues, their feed URLs, and a
music-relevance guess." The enable is always a reviewed code/ledger change.
Rationale: scrapers mint every genre they see (taxonomy pollution for *all* users
before curation), a new source can pull non-music / mis-tag / break on JS /
violate robots, and the blast radius of a bad add is every visitor while the cost
of a missed add is one venue found next week — asymmetric risk → human in the
loop. Auto-*classification* (pre-sorting the delta, auto-filing an exact
reject-alias match) is safe; auto-*consumption* is not. The line is bright: the
report can sort and hide, it can never enable a feed.
