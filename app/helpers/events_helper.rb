module EventsHelper
  # The calendar's open day lives in the URL (?day=YYYY-MM-DD) so it is linkable,
  # survives reload, and is what the server renders. These keep the rest of the
  # URL state (filter, focused month) intact while toggling just the open day.
  def calendar_day_path(date)
    events_path(calendar_state_params.merge('day' => date.iso8601))
  end

  def calendar_collapse_path
    events_path(calendar_state_params)
  end

  def calendar_state_params
    request.query_parameters.except('day', 'page').merge('view' => 'calendar')
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

  # A tag on an event (venue, location, style). Filtering the programme is done in
  # the filter inputs, not by clicking tags — so for a logged-in visitor the whole
  # tag is instead the *follow* toggle (see #favorite_tag). Logged-out visitors
  # can't follow, so they get a plain label. In read-only contexts (e.g. a
  # notification digest) there's no filter form, so it stays a link into the
  # filtered list as a way back into the site.
  def event_filter_tag(label, field:, value:, interactive: true, modifier: nil, favorite_type: nil)
    unless interactive
      return link_to label, events_path(field.delete_suffix('[]').to_sym => [value]),
                     class: class_names('filter-link', modifier)
    end

    return content_tag(:span, label, class: class_names('event-tag', modifier)) unless favorite_type && authenticated?

    favorite_tag(label, favorite_type, value, modifier)
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
        content_tag(:span, '', class: 'fav-heart', 'aria-hidden': true)
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
  # styles compared as sets, order-independent). When on, the control reads as
  # active and a click clears it back to the full programme.
  def favorites_filter_active?
    favorites_filter_available? &&
      Set.new(@filter.location_list) == followed_locations &&
      Set.new(@filter.style_list) == followed_styles
  end

  # The current user's saved event ids, loaded once so the per-event save button
  # doesn't N+1 across a list.
  def saved_event_ids
    @saved_event_ids ||= Set.new(current_user&.event_saves&.pluck(:event_id))
  end

  def event_saved?(event)
    saved_event_ids.include?(event.id)
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
      # solid, mirroring the follow heart's outline→fill — see .save-bookmark.
      content_tag(:span, '', class: 'save-bookmark', 'aria-hidden': true)
    end
  end
end
