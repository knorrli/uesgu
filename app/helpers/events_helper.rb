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
  # finger-sized chip). Following moved off the tag onto the dedicated "follow this
  # filter" control (see _notify_button), which frees colour to mean the app's
  # usual "this is interactive" again. favorite_type: is kept for call-site
  # compatibility.
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
  def event_filter_tag(label, field:, value:, interactive: true, modifier: nil, favorite_type: nil)
    param = field.delete_suffix('[]')

    unless interactive
      return link_to label, events_path(param.to_sym => Array(value)),
                     class: class_names('filter-link', modifier)
    end

    applied = request.query_parameters.except('page')
    current = Array(applied[param])
    matched = filter_terms_matching(current, value, param: param)
    active = matched.any?
    values = active ? current - matched : current + [value.to_s]
    query = values.any? ? applied.merge(param => values) : applied.except(param)

    link_to label, events_path(query),
            class: class_names('filter-link', modifier, active: active),
            data: { turbo_frame: '_top' }
  end

  # The applied terms that "match" a tag — the ones that light it green and that
  # tapping it removes. Freetext (q[]) matches by CONTAINS (the tag contains the
  # applied term), so sibling descriptors light up instead of only exact hits;
  # everything else matches exactly. Case-insensitive.
  def filter_terms_matching(applied_terms, value, param:)
    if param == 'q'
      haystack = value.to_s.downcase
      applied_terms.select { |term| haystack.include?(term.to_s.downcase) }
    else
      applied_terms.select { |term| term.to_s == value.to_s }
    end
  end

  # The whole tag is the follow toggle: clicking the venue/style name (a big,
  # obvious target, not a tiny icon) follows/unfollows it, shown by a trailing
  # heart that inherits the tag's size. Optimistic — the favorite Stimulus
  # controller flips every matching tag on the page and POSTs in the background,
  # so nothing reloads. At rest a followable tag looks like plain info (a faint
  # outline heart is the only "you can follow this" cue, so the list reads the same
  # logged in or out); following it fills the heart and lights the tag in the
  # accent colour — the one place colour now means "this is yours".
  def favorite_tag(label, type, value, modifier = nil)
    followed = followed_tag?(type, value)
    button_tag type: :button,
               class: class_names('event-tag', 'fav', modifier, followed: followed),
               'aria-pressed': followed.to_s,
               'aria-label': t('favorites.toggle', name: value),
               data: { action: 'favorite#toggle', favorite_type_param: type, favorite_value_param: value } do
      safe_join([
        content_tag(:span, label, class: 'fav-label'),
        content_tag(:span, '', class: 'fav-star', 'aria-hidden': true)
      ])
    end
  end

  def followed_tag?(type, value)
    case type.to_sym
    when :location then followed_locations.include?(value)
    when :style then followed_styles.include?(value)
    else false
    end
  end

  # The current user's follows, loaded once per request and reused across every
  # tag in the list (a style repeats on many events; a venue on many days).
  def followed_locations
    @followed_locations ||= Set.new(current_user&.location_list)
  end

  def followed_styles
    @followed_styles ||= Set.new(current_user&.style_list)
  end

  # The user's follows as namespaced keys ("l:<location>" / "s:<style>"). Used to
  # render each day's heart marker server-side (the authoritative source on every
  # render) and handed to the favorite Stimulus controller so it can flip those
  # markers the instant a tag is toggled. See CalendarHelper#calendar_day_favorite_keys.
  def favorite_followed_keys
    followed_locations.map { |name| "l:#{name}" } + followed_styles.map { |name| "s:#{name}" }
  end

  # Offer the "filter to my favorites" shortcut only to a logged-in user who has
  # at least one followed location or style — otherwise there is nothing to apply.
  def favorites_filter_available?
    current_user.present? && (followed_locations.any? || followed_styles.any?)
  end

  # True when the active filter is exactly the user's favorites (locations and
  # styles, order-independent, and no extra free-text query). When on, the control
  # reads as active and a click clears it back to the full programme.
  def favorites_filter_active?
    favorites_filter_available? && current_user.favorites_filter?(@filter)
  end

  # The current user's saved event ids, loaded once so the per-event save button
  # doesn't N+1 across a list.
  def saved_event_ids
    @saved_event_ids ||= Set.new(current_user&.event_saves&.pluck(:event_id))
  end

  def event_saved?(event)
    saved_event_ids.include?(event.id)
  end

  # True when an event touches one of the user's follows — a followed location or
  # style. In-memory over already-loaded associations + the cached followed sets,
  # so it stays cheap across a calendar month. Used to pick a cell's interest
  # headline (see CalendarHelper#calendar_day_headline).
  def event_matches_follow?(event)
    event.locations.any? { |location| followed_locations.include?(location.name) } ||
      event.styles.any? { |style| followed_styles.include?(style.name) }
  end

  # The bookmark toggle on an event. Logged-in only; optimistic via the `save`
  # Stimulus controller (one self-contained controller per button, no cross-sync).
  def event_save_button(event)
    return unless authenticated?

    saved = event_saved?(event)
    button_tag type: :button,
               class: class_names('event-save', 'icon-button', saved: saved),
               'aria-pressed': saved.to_s,
               'aria-label': t('saved_events.toggle'),
               data: { controller: 'save', action: 'save#toggle',
                       save_event_id_value: event.id, save_saved_value: saved } do
      # A masked bookmark (not the ph font glyph) so the saved state can fill
      # solid, mirroring the follow heart's outline→fill — see .save-heart.
      content_tag(:span, '', class: 'save-heart', 'aria-hidden': true)
    end
  end
end
