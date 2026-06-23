# Email + domain migration to Infomaniak

**Status (2026-06-22): PARKED — waiting on Metanet transfer codes** (requested
2026-06-22, "delivered within one working day", so ~2026-06-23). Resume at Phase 2
once the codes arrive.

## Goal

Give `kontakt@uesgu.ch` a real inbox so the footer's **Datenschutz** page has a
working contact address. Decided to **consolidate registration + DNS onto
Infomaniak** rather than scatter them (DNS at Metanet, mail elsewhere).

**Why Infomaniak:** it includes **one free, full mailbox** with every domain it
*manages* — no Mail Service / kSuite subscription, you only pay the annual domain
fee. `.ch` transfer is free + immediate. Swiss, privacy-aligned, and it sits with
the dedicated `@ik.me` account already created for this. (ForwardEmail/ImprovMX
forwarding was considered and dropped — third-party hop + mixed reviews.)

Downtime is acceptable (personal tool), which removes the need for fragile
pre-staging.

## Current DNS — the source of truth to rebuild

Pulled from the authoritative nameserver (`@ch.pro.io`) on 2026-06-22. Rebuild
these **exactly** in Infomaniak's DNS zone. **Before transferring, also grab a
full backup via Metanet's `BIND-Export` button** (DNS-Verwaltung tab) and save the
file alongside this doc.

### `uesgu.ch` (web app + email-sending domain)

| Type | Host | Value | Priority |
|---|---|---|---|
| A | `@` | `216.24.57.1` | — |
| CNAME | `www` | `uesgu.onrender.com.` | — |
| MX | `send` | `feedback-smtp.eu-west-1.amazonses.com.` | 10 |
| TXT | `send` | `v=spf1 include:amazonses.com ~all` | — |
| TXT | `resend._domainkey` | `p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC1FoibNpmFlcCqyHkk1oMDy47mv2Nw1EK5xwX2zPdwDFMj6r+oTBHNmOwZgNJMJjt/EfwRSK8Z7ccGpYGDU7lKPAZmavKqSc7EQfhza8NPbjIGTqDdPQ32lkhJXSn368G3xV+jgIFeb7QJaUw9MBpOMC7z9F6mYG1m84YSTqscTwIDAQAB` | — |
| TXT | `_dmarc` | `v=DMARC1; p=none;` | — |

The `send` / `resend._domainkey` / `_dmarc` records are the **Resend sending
setup** — they must survive identically or outbound mail + DMARC alignment break.
No apex MX/SPF exists today (the mailbox step adds those).

### `üsgu.ch` (`xn--sgu-goa.ch`, public domain — no mail)

| Type | Host | Value |
|---|---|---|
| A | `@` | `216.24.57.1` |
| CNAME | `www` | `uesgu.onrender.com.` |

`216.24.57.1` is Render's apex IP; the `www` CNAMEs point at the Render app. Both
must be recreated or the site goes dark.

## Infomaniak panel map (to stop bouncing between UIs)

- **`manager.infomaniak.com`** — admin Manager; everything is a "product" via the
  top-left switcher.
  - **Domains** product → transfer, registration, **DNS zone editor**.
  - **Mail Service** product → create/manage the `kontakt@uesgu.ch` address.
- **`mail.infomaniak.com`** (or the Mail app) — webmail, only for reading/sending.
  No configuration here.

## Runbook

### Phase 1 — Metanet: release the domains ✅ (codes requested)

1. ✅ Requested **Transfer-Code** for `uesgu.ch` (and do `üsgu.ch` too) — delivered
   within ~1 working day.
2. Ensure the **domain lock** is off (Domain-Verwaltung).
3. Ignore the SOA "Kontakt" (`hostmaster@uesgu.ch`) field — it's the zone's
   informational contact, **not** used for the transfer, and it disappears when DNS
   moves. `.ch` transfers are authorized by the **code**, not an email approval.
4. Do **not** hit Kündigung in a way that deletes the domain — the transfer is the
   clean exit. Requesting the code already signals the subscription is ending.

### Phase 2 — Infomaniak: start the transfer

5. Manager → **Domains** → **Transfer a domain**. Enter `uesgu.ch` + its code;
   repeat for `üsgu.ch` (enter as the IDN). `.ch` = free, usually quick.
6. When prompted about email, choose the **"1 free email address (Starter)"** for
   `uesgu.ch`.
7. **Registrant/owner email:** use the dedicated `@ik.me` (or `kontakt@uesgu.ch`
   once it exists), **not** a personal address. `.ch` WHOIS is redacted by SWITCH,
   so holder data isn't public regardless.

### Phase 3 — Infomaniak: rebuild the DNS zone

8. Manager → Domains → the domain → **DNS zone**. Infomaniak generates a default
   zone: **delete its placeholder/parking records** (default `A`, default `www`,
   any default mail records you didn't ask for), then recreate everything from the
   inventory tables above — for **both** domains.
9. Copy the long `resend._domainkey` value from the Metanet record / BIND export
   rather than retyping it. It's one single TXT string.

### Phase 4 — Infomaniak: create the mailbox

10. Manager → **Mail Service** → create **`kontakt@uesgu.ch`** (set a password).
    With DNS now on Infomaniak's nameservers, it auto-adds the apex **MX + SPF +
    DKIM** for mail.
11. Re-open the DNS zone: confirm the mail records were added and did **not**
    clobber `A @ → 216.24.57.1`, the `www` CNAME, or the three Resend records.
    Ensure exactly **one** `_dmarc` and **one** apex SPF.

### Phase 5 — cut over the nameservers

12. Point both domains at **Infomaniak's nameservers** (usually automatic once you
    use their DNS). Propagation up to 24–48 h (downtime OK).

### Phase 6 — verify (Claude runs the `dig` checks)

13. `dig` confirms: NS = Infomaniak; `A @` = `216.24.57.1`; `www` CNAME intact; new
    Infomaniak `MX` on `uesgu.ch`; `send` / `resend._domainkey` / `_dmarc` all
    still present.
14. Functional: open `https://üsgu.ch` (site loads; Render re-issues TLS after the
    NS change — a short blip is fine); send a test from another account to
    `kontakt@uesgu.ch` (lands in Infomaniak webmail); trigger an app email to
    confirm **Resend still sends**.

### Phase 7 — finish

15. Stop paying Metanet (registration has moved).
16. Flip the footer's Datenschutz contact from plain text to a real address if
    desired (we currently keep it **plain text** as an anti-harvest choice — see
    `app/views/pages/privacy.html.erb`). Mailbox being live unblocks the contact.

## Gotchas

- **Resend records must survive identically** — `send` MX+TXT, `resend._domainkey`
  TXT, `_dmarc` TXT. Losing/altering them breaks outbound mail.
- **Render `A` + `www` records** must be recreated or the site goes dark.
- **Two domains**, not one: `uesgu.ch` *and* `üsgu.ch` (`xn--sgu-goa.ch`).
- Only **one** `_dmarc` and **one** apex SPF after the mailbox auto-config.
- The Infomaniak free mailbox needs the **registration** at Infomaniak; DNS being
  there too is what auto-configures the mail records.
