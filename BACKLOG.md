# üsgu — Backlog

> Single source of truth for **what's left**. If an open item isn't here, it
> isn't tracked. This file carries open work only — not history. üsgu is a
> **personal tool**: functional completeness is met; remaining work is polish
> plus a few open items.

## Planned

- **Footer + "Über üsgu" / Datenschutz pages.**
  - New `shared/_footer` partial in the app layout + a styleguide specimen.
    Recessive (muted, small), in-flow (not sticky).
  - Two links: **Über üsgu** (name chosen for the alliteration) and **Datenschutz**.
  - *Über üsgu* — first-person, in voice: what üsgu is, why it was made, the
    privacy-first stance. Static page, own route/controller in the vein of `install`.
  - *Datenschutz* — short revDSG notice (username, optional email, theme cookie;
    not shared/sold; how to delete the account), ending with a contact line
    `kontakt@uesgu.ch`. **No Impressum, no real name** — non-commercial hobby site,
    so the UWG e-commerce imprint duty doesn't apply.
  - i18n in de/fr/en (French stays informal `tu`).
  - 🚫 **BLOCKER:** set up inbound email forwarding `kontakt@uesgu.ch` → personal
    inbox (Cloudflare Email Routing or registrar forwarding; Resend is outbound-only,
    can't receive). Until live, the contact ships as plain text, not a working link.
  - ⚠️ Datenschutz wording is **not lawyer-reviewed** — sanity-check before relying on it.

## Maybe-later (explicitly deferred)

- **"Party spotlight" animated loader.** An in-app animated loader (HTML/CSS/SVG,
  rendered after the PWA boots) that brings the mark's spotlight cones to life —
  genuinely dynamic motion the static iOS splash can't do (it's a pre-boot image).
  The static asymmetric mark already ships via `script/generate_icons.rb`; this is
  the separate motion follow-up.
- Session "Update the filter I just applied" soft-pointer.
- `featured`/`main_genre` flag + subtree-count browse ranking.

## Out of scope (not "incomplete")

- More scraper venues — candidate/evaluated venues live in `config/venue_ledger.yml` (defer/reject rows); discovery via `docs/discovery-design.md`.
- Richer event fields (`price` / `image`) — **rejected.** Image hotlinking leaks
  the viewer's IP to every venue (against the privacy-first ethos) and proxying is
  not worth the cost for a personal tool; price adds little. The proposal's other
  two fields shipped differently: `description` + `lineup` collapsed into the single
  curated `description` field (the `subtitle`→`description` rename + per-source
  curation). Audit retained for reference at `docs/richer-fields-proposal.md` (now
  closed). Genre-mining from dropped prose also shipped (`event_genre_prose`).
- Vanished-event sweep / ratio alerting — declined as over-engineering.
- Password reset — no recovery flow by design.
