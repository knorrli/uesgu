module EventsHelper
  # A filterable term (venue, location, style). In the interactive events list
  # it's a toggle button wired to the filter Stimulus controller; in read-only
  # contexts (e.g. a notification digest) it's a plain link to the filtered list,
  # so green still means "clickable" without needing a live filter form.
  def event_filter_tag(label, field:, value:, interactive: true, active: false, modifier: nil, favorite_type: nil)
    classes = class_names('filter-link', modifier, active: active)

    tag = if interactive
      button_tag label, type: :button, class: classes,
                 data: { action: 'filter#toggleFilter', filter_field_name_param: field, filter_value_param: value }
    else
      link_to label, events_path(field.delete_suffix('[]').to_sym => [value]), class: classes
    end

    # Inline favoriting only makes sense in the live list for a logged-in user;
    # digests (interactive: false) and logged-out visitors get the bare tag.
    return tag unless interactive && favorite_type && authenticated?

    safe_join([tag, favorite_toggle(favorite_type, value)])
  end

  # A heart that follows/unfollows one location or style for the current user.
  # The favorite Stimulus controller flips every matching heart on the page and
  # POSTs in the background, so the list never reloads; colour carries state
  # (themify only ships an outline heart), matching the "green = active" language.
  def favorite_toggle(type, value)
    followed = followed_tag?(type, value)
    # Empty button: the heart glyph (outline/solid) comes from CSS so state lives
    # in one place (the `followed` class) for both the colour and the fill.
    button_tag '', type: :button,
               class: class_names('fav-toggle', followed: followed),
               'aria-pressed': followed.to_s,
               'aria-label': t('favorites.toggle', name: value),
               data: { action: 'favorite#toggle', favorite_type_param: type, favorite_value_param: value }
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
end
