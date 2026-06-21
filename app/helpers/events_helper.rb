module EventsHelper
  # The calendar's open day lives in the URL (?day=YYYY-MM-DD) so it is linkable,
  # survives reload, and is what the server renders. These keep the rest of the
  # URL state (filter, focused month) intact while toggling just the open day.
  # Route-agnostic (via url_for) so the same calendar partials drive both the
  # main programme and the saved-shows list.
  def calendar_day_path(date)
    calendar_listing_path(calendar_state_params.merge('day' => date.iso8601))
  end

  def calendar_collapse_path
    calendar_listing_path(calendar_state_params)
  end

  def calendar_state_params
    request.query_parameters.except('day', 'page').merge('view' => 'calendar')
  end

  # Listing/aggregator hosts (eTLD+1 → friendly name) we link OUT to when an event
  # has no page on the venue's own site. Keyed on the link HOST, not data_source:
  # an aggregator scraper (Petzi, OLE:Bewegungsmelder) links to the venue's own
  # page when one exists, so only the genuinely off-site links get badged. Add a
  # row when a new source can land users somewhere other than the venue.
  OFFSITE_SOURCES = {
    'bewegungsmelder.ch' => 'Bewegungsmelder',
    'eventfrog.ch'       => 'Eventfrog',
    'petzi.ch'           => 'PETZI'
  }.freeze

  # The friendly name of the listing site an event's link points at, or nil when
  # it points at the venue's own site (the common case → no badge). Lets the event
  # card flag "this link leaves you at Bewegungsmelder, not the venue".
  def event_offsite_source(event)
    host = URI.parse(event.url.to_s).host&.downcase&.delete_prefix('www.')
    return nil if host.blank?

    OFFSITE_SOURCES[host] || OFFSITE_SOURCES.find { |domain, _| host.end_with?(".#{domain}") }&.last
  rescue URI::InvalidURIError
    nil
  end

  # Build a path to the *current* listing (events_path or saved_events_path) from
  # a query hash — url_for fills the controller/action from the live request.
  def calendar_listing_path(query)
    url_for(query.merge(only_path: true))
  end

  # simple_calendar builds its month-nav links by merging the *current* query —
  # which would drag a now-irrelevant open day into the next month. Drop it so
  # changing months collapses any open day. Other state (filter) is preserved.
  def calendar_nav_path(url)
    uri = URI.parse(url)
    query = Rack::Utils.parse_nested_query(uri.query).except('day')
    uri.query = query.presence && query.to_query
    uri.to_s
  end

  # A taxonomy term on an event — venue, city/canton, style, or genre. Tapping it
  # FILTERS the programme by that term ("tap rock → rock events"), the behaviour
  # cold users expect. One action per tag: the whole tag is the filter link, so a
  # tag means exactly one thing (no tiny secondary follow target crammed onto a
  # finger-sized chip). Following was removed entirely (the ★ saves a whole filter
  # instead — see _save_notify), which frees colour to mean the app's usual "this
  # is interactive" again.
  #
  # The tap TOGGLES the filter by this term, and the highlight follows MATCHING,
  # not exact equality. A tag lights green when an applied filter matches it — for
  # the freetext path (q[], how genres are tapped) that means CONTAINS: filter
  # "metal" lights "Metal", "Dark Metal", "Death Metal", not just an exact "metal".
  # The rule the user reads is "green = you're filtering by this":
  #   • tap a GREY tag → add it (its own term);
  #   • tap a GREEN tag → remove the applied term(s) that matched it (e.g. tapping
  #     the lit "Dark Metal" while filtering "metal" drops "metal" and broadens).
  # Locations (l[]) match exactly — a substring venue would be nonsense. Page is
  # reset so you land on page 1. In a read-only context (no filter form, e.g. a
  # notification digest passing interactive: false) it stays a plain single-value
  # link into the listing — a way back into the site.
  def event_filter_tag(label, field:, value:, interactive: true, modifier: nil)
    param = field.delete_suffix('[]')

    unless interactive
      return link_to label, events_path(param.to_sym => Array(value)),
                     class: class_names('filter-link', modifier)
    end

    applied = request.query_parameters.except('page')

    # Which applied filter params light this tag, and the match RULE for each (the
    # rule is keyed to the APPLIED param, not the tag, so one tag can answer to two
    # axes). A genre tag (g) lights from a genre filter (g, subtree match) OR a
    # freetext term (q, CONTAINS on the genre name) — so typing "hop" lights
    # "Hip Hop" just like picking a parent genre does. Anything else matches its
    # own param exactly (locations).
    matchers =
      case param
      when 'g' then { 'g' => 'g', 'q' => 'q' }
      else { param => param }
      end
    matched = matchers.to_h { |p, rule| [p, filter_terms_matching(Array(applied[p]), value, param: rule)] }
    active = matched.values.any?(&:present?)

    query = applied.dup
    if active
      # Tap GREEN → drop every applied term that lit this tag, across all the axes
      # that matched it (e.g. a genre tag lit by both a g[] ancestor and a q[]
      # freetext clears both).
      matched.each do |p, terms|
        next if terms.empty?
        rest = Array(applied[p]) - terms
        rest.any? ? query[p] = rest : query.delete(p)
      end
    else
      # Tap GREY → add it (its own term, on its own param).
      query[param] = Array(applied[param]) + [value.to_s]
    end

    link_to label, events_path(query),
            class: class_names('filter-link', modifier, active: active),
            data: { turbo_frame: '_top' }
  end

  # The applied terms that "match" a tag — the ones that light it green and that
  # tapping it removes. Free text (param 'q') matches by CONTAINS (the tag contains
  # the applied term), so sibling descriptors light up instead of only exact hits;
  # genres (param 'g') match by subtree membership; locations match exactly.
  # Case-insensitive.
  def filter_terms_matching(applied_terms, value, param:)
    case param
    when 'q'
      haystack = value.to_s.downcase
      applied_terms.select { |term| haystack.include?(term.to_s.downcase) }
    when 'g'
      # A genre tag lights when an applied genre filter's SUBTREE contains it —
      # descendant-set membership, reusing the same tree expansion Filter matches
      # with (so filtering "Rock" lights a row's "Shoegaze"). Tapping it removes
      # that ancestor term, broadening the filter (the toggle semantics below).
      applied_terms.select { |term| genre_subtree_names(term).include?(value.to_s) }
    else
      applied_terms.select { |term| term.to_s == value.to_s }
    end
  end

  # The set of genre names a picked filter term matches — the term's subtree plus
  # any alias resolving into it (see Genre.filter_names_for, shared with the filter
  # query so match and highlight can't drift). Memoised per request so a genre
  # repeated across many rows costs one lookup, not one per tag.
  def genre_subtree_names(term)
    (@genre_subtree_names ||= {})[term.to_s] ||= Set.new(Genre.filter_names_for(term))
  end

  # The current user's saved event ids, loaded once so the per-event save button
  # doesn't N+1 across a list.
  def saved_event_ids
    @saved_event_ids ||= Set.new(current_user&.event_saves&.pluck(:event_id))
  end

  def event_saved?(event)
    saved_event_ids.include?(event.id)
  end

  # ── Interest highlighting (derived from saved filters) ─────────────────────
  # "Could interest me" = matches one of my saved filters, date window ignored.
  # Built once per request; see InterestProfile.
  def interest_profile
    @interest_profile ||= InterestProfile.for(current_user)
  end

  def interest_event?(event)
    interest_profile.interesting?(event)
  end

  # A genre worth flagging as "why this interests me": it explains a match AND
  # isn't already an applied (green) filter term — so amber never doubles green.
  def interest_why_genre?(event, genre)
    return false unless interest_profile.any?
    return false if applied_filter_term?('g', genre.name)

    interest_profile.why_genres(event).include?(genre)
  end

  # The location names across a venue group that explain an interest match and
  # aren't already applied — a Set the venue header checks per token (venue + meta).
  def interest_location_names(events)
    return Set.new unless interest_profile.any?

    Array(events)
      .flat_map { |event| interest_profile.why_locations(event) }
      .map(&:name)
      .reject { |name| applied_filter_term?('l', name) }
      .to_set
  end

  # Mirrors the "is this tag in your applied filter" test in event_filter_tag: a
  # genre lights from a g[] subtree or a q[] CONTAINS, a location matches exactly.
  def applied_filter_term?(param, value)
    applied = request.query_parameters.except('page')
    matchers = param == 'g' ? { 'g' => 'g', 'q' => 'q' } : { param => param }
    matchers.any? { |applied_param, rule| filter_terms_matching(Array(applied[applied_param]), value, param: rule).present? }
  end

  # The saved-show heart toggle on an event. Logged-in only; optimistic via the
  # `save` Stimulus controller (one self-contained controller per button, no cross-sync).
  def event_save_button(event)
    return unless authenticated?

    saved = event_saved?(event)
    button_tag type: :button,
               class: class_names('event-save', 'icon-button', saved: saved),
               'aria-pressed': saved.to_s,
               'aria-label': t('saved_events.toggle'),
               data: { controller: 'save', action: 'save#toggle',
                       save_event_id_value: event.id, save_saved_value: saved } do
      # A masked heart (not the ph font glyph) so the saved state can fill solid,
      # outline→fill — see .save-heart.
      content_tag(:span, '', class: 'save-heart', 'aria-hidden': true)
    end
  end
end
