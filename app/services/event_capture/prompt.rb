module EventCapture
  # What we send Gemma. Deliberately a copy of the prompt in
  # script/event_capture_bakeoff.rb rather than a shared constant: that script is a
  # frozen evaluation harness whose sessions record a `prompt_sha`, and editing it
  # would silently break the comparability of the runs the provider decision rests
  # on. It stays the tuning rig; this is production.
  #
  # Two substantive edits against the bake-off text, both from
  # docs/user-event-capture-design.md: the field is `locality`, not `city` (ask for
  # a city and the model nulls out on a hamlet — the exact field match-at-entry
  # depends on), and locality is defined as the tier below canton rather than left
  # to mean whatever "city" means.
  #
  # Everything else is verbatim, and should stay that way. The evidence rule below
  # is most of the difference between 0/6 and 5/6 fabricated dates, and prompt
  # tuning was measured NOT to transfer between models — treat any edit here as
  # something to re-run the bake-off over.
  #
  # The text medium (#105) is the one addition. The rules are shared because the
  # rules are the tuned part; only the phrases that name the medium differ, and they
  # are collected in MEDIA rather than scattered so the image rendering stays
  # word-for-word what the bake-off measured. It is UNMEASURED against the sample
  # set, which is six images: the bake-off cannot score a text prompt without text
  # ground truth, and #112 is what will say whether it needs tuning of its own.
  #
  # The one image-side change: SCHEMA is a single frozen constant shared by both
  # media, so its field descriptions say "the input" where they used to say "the
  # image" — true of both, and cheaper than building the schema per call.
  module Prompt
    MEDIA = {
      image: {
        corpus: "images",
        input: "a photographed poster, a flyer, or a screenshot of a chat message",
        legible: "text you can actually read in the image",
        says: "what the image says",
        unit: "ONE IMAGE MAY ADVERTISE SEVERAL EVENTS",
        chrome: "In a messaging screenshot",
        chrome_tail: "If the only date-like thing in a screenshot is chat chrome",
        emphasis: "The largest text on a poster is usually the ARTIST, not the venue.",
        quoted: "If the image says",
        only_from: "ONLY from something in the image",
        looks_swiss: "because the image looks Swiss",
        elsewhere: "on the poster",
        names_it: "image",
        genre_src: "the image",
        own_wording: "the poster's",
        request: "Extract every event advertised in this image. JSON only."
      },
      text: {
        corpus: "text",
        input: "text copied from a web page, from a chat message, or typed out from a poster",
        legible: "text that actually appears in the input",
        says: "what the text says",
        unit: "ONE INPUT MAY ADVERTISE SEVERAL EVENTS",
        chrome: "In a pasted chat transcript",
        chrome_tail: "If the only date-like thing in the input is chat chrome",
        emphasis: "A page's site name, its navigation and its biggest heading are usually not the venue.",
        quoted: "If the text says",
        only_from: "ONLY from something in the text",
        looks_swiss: "because the text looks Swiss",
        elsewhere: "in the text",
        names_it: "input",
        genre_src: "the text",
        own_wording: "the input's",
        request: "Extract every event advertised in the text below. JSON only."
      }
    }.freeze

    module_function

    def request(medium: :image) = MEDIA.fetch(medium)[:request]

    def instructions(today:, medium: :image)
      m = MEDIA.fetch(medium)

      <<~TXT
        You extract concert/event listings from #{m[:corpus]} for a Swiss (Bern-area) event
        site. Input is #{m[:input]}. Text is usually German, sometimes French or English.

        Today is #{today}.

        THE EVIDENCE RULE — this governs everything below.

        Every `date` and every `place` you return MUST be copied from #{m[:legible]},
        and you must quote that text verbatim in
        `date_evidence` / `place_evidence`. If you cannot quote it, the field is null
        and the evidence field is null. Never supply a value you cannot cite.

        You are NOT being asked to identify the venue. You are being asked to
        transcribe #{m[:says]}. A plausible guess is worse than null: a wrong
        venue silently creates a fake location in our database, whereas a null is
        simply completed by a human in one tap.

        Rules:

        1. #{m[:unit]}. A poster listing two dates is two
           events. A festival timetable with three time slots is three events. Return
           every one of them.

        2. CHAT UI IS NOT EVENT DATA. #{m[:chrome]}, ignore completely:
           day separators ("Saturday", "Yesterday", "Sunday"), message timestamps
           (10:29, 13:43), sender names and phone numbers, reactions, unread badges,
           the status bar. A "Saturday" divider tells you when the MESSAGE was sent.
           It NEVER tells you when the event happens. #{m[:chrome_tail]},
           the event has NO date: return null.

        3. Most posters state no year. Resolve a bare date ("26.8.", "Sa. 08.08.") to
           the nearest occurrence. If a weekday is printed, use it as a checksum —
           "Donnerstag 20 August" only fits a year in which 20 August is a Thursday.
           Do NOT roll a past date forward to next year; return the date as printed
           resolves.

        4. `place` is the VENUE OR LOCATION, transcribed exactly as printed. Watch out:
           - #{m[:emphasis]}
           - A band name is not a venue.
           - "auf der Dachterrasse" / "im Park" describes where inside a place — the
             place itself is the name printed elsewhere #{m[:elsewhere]}.
           - Never substitute a venue you happen to know exists in that city. #{m[:quoted]}
             "ZAR", the answer is "ZAR" — not a café with a similar name.
           - Copy spelling exactly, including K vs C and umlauts. We match these
             against a venue database; one wrong letter means no match.

        5. `locality` / `canton` #{m[:only_from]}: a street address, a
           postcode, a neighbourhood name, a URL. Otherwise null. Do not guess "Bern"
           #{m[:looks_swiss]}. `locality` is the next level of detail below
           the canton — a city, a town, a village, a hamlet or a quarter, whichever the
           #{m[:names_it]} actually names. A hamlet is a perfectly good answer; do not reach for
           the nearest city because it is better known.

        6. Read URLs — a venue is often identifiable only from a link. Put the event
           link in source_url.

        7. `genres` only if #{m[:genre_src]} names them. Do not classify the music yourself.
           If a genre line is cut off mid-word, omit it rather than guessing the rest.

        8. `title` is the act or event name. Transcribe unfamiliar names character by
           character — these are small local acts you will not recognise, so do not
           "correct" a name toward one that sounds more familiar.

        FORMATS — these are strict:
          date  exactly YYYY-MM-DD, e.g. "2026-08-20". Never a datetime, never
                "20.08.2026", never #{m[:own_wording]} own wording. The evidence field is
                where the original wording goes.
          time  exactly HH:MM on a 24-hour clock, e.g. "20:00". "20 Uhr" becomes
                "20:00"; "19.30h" becomes "19:30". No suffixes, no seconds.
          canton  the 2-letter uppercase code, e.g. "BE".
        A value in any other shape is discarded, so the work is wasted — emit null
        rather than a differently-formatted value.

        Return ONLY a JSON object matching the provided schema. No prose, no markdown.
      TXT
    end

    # OpenAI-style structured output. Infomaniak rejects the older `json_object` mode
    # outright ("no longer supported... please use 'json_schema'"), and strict mode is
    # better anyway: it forces every field to be present, so a model that simply omits
    # `date` cannot be read as if it thoughtfully returned null. strict mode requires
    # every property in `required` and additionalProperties false.
    SCHEMA = {
      name: "extracted_events",
      strict: true,
      schema: {
        type: "object",
        additionalProperties: false,
        required: ["events"],
        properties: {
          events: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: %w[title date date_evidence time place place_evidence locality canton genres source_url],
              properties: {
                title:          { type: %w[string null] },
                date:           { type: %w[string null], description: "YYYY-MM-DD, or null if not legible" },
                date_evidence:  { type: %w[string null],
                                  description: "Verbatim text from the input the date was read from. null if the date is null." },
                time:           { type: %w[string null], description: "HH:MM 24h, or null" },
                place:          { type: %w[string null] },
                place_evidence: { type: %w[string null],
                                  description: "Verbatim text from the input the place was read from. null if the place is null." },
                locality:       { type: %w[string null],
                                  description: "City, town, village, hamlet or quarter named in the input" },
                canton:         { type: %w[string null], description: "2-letter Swiss canton code" },
                genres:         { type: "array", items: { type: "string" } },
                source_url:     { type: %w[string null] }
              }
            }
          }
        }
      }
    }.freeze
  end
end
