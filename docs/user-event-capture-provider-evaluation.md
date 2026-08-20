# User event capture — provider evaluation

> The measurement that settled the extraction provider, kept whole because it is the
> answer to "why not just use a US model", which gets asked again. The decisions it
> fed are in [`user-event-capture-design.md`](user-event-capture-design.md); this file
> is the evidence under them and does not change as the feature is built on.

## The question

Sending user images to a US provider sits badly with the privacy stance
([`project-product-ethos`]). Cost turned out to be irrelevant: at ~5 captures/day
every candidate lands between **$0.06 and $5.00 per month**, so the decision is
sovereignty and accuracy only. That also kills the cost case for self-hosting — a
GPU box costs more than $5/month in electricity alone, before ops.

## Method

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

## Results

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
an image; text input arrives with the adapters, which is also where image
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

## Two findings worth keeping

**Prompt tuning does not transfer between models.** The prompt revision that took
Gemma from 17% to 0% fabrication pushed Mistral from 40% to 83% on identical
inputs. Re-tune per model; never assume a prompt improvement is portable.

**Confidence scores are worthless here.** The first prompt asked for a
`confidence` field; it returned 0.90–1.00 on every output *including* an invented
venue ("Café Liebig", not present in the image) and three fabricated dates. The
field was removed. Do not gate anything on self-reported confidence.

## What made the difference

Requiring **verbatim citation** — every `date` and `place` must be accompanied by
`date_evidence` / `place_evidence` quoting the image text it was read from, or be
null. This is most of the gain, and it yields a free fabrication detector: a
populated value with a null evidence field is self-reported invention.

Naming the exact trap also mattered. The fabricated dates all came from the
WhatsApp "Saturday" day-separator, so the prompt now says explicitly that a
separator tells you when the *message* was sent, never when the event happens.
