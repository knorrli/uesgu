module EventsHelper
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
  # so nothing reloads. Accent colour marks a tag as followable; the heart's fill
  # marks whether you currently follow it.
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

  # The user's follows as namespaced keys ("l:<location>" / "s:<style>"). Handed
  # to the favorite Stimulus controller so it can recompute calendar day markers
  # client-side as tags are toggled. See CalendarHelper#calendar_day_favorite_keys.
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
end
