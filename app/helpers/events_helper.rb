module EventsHelper
  OFFSITE_SOURCES = {
    "bewegungsmelder.ch" => "Bewegungsmelder",
    "eventfrog.ch"       => "Eventfrog",
    "facebook.com"       => "Facebook",
    "instagram.com"      => "Instagram",
    "petzi.ch"           => "PETZI"
  }.freeze

  VenueLink = Data.define(:name, :url)

  def event_link_url(event)
    event.url.presence || event_venue_link(event)&.url
  end

  def event_venue_link(event)
    event.locations.each do |location|
      url = venue_urls[Fingerprint.for(location.name)]
      return VenueLink.new(name: location.name, url: url) if url
    end
    nil
  end

  def event_offsite_source(event)
    host = URI.parse(event_link_url(event).to_s).host&.downcase&.delete_prefix("www.")
    return nil if host.blank?

    OFFSITE_SOURCES[host] || OFFSITE_SOURCES.find { |domain, _| host.end_with?(".#{domain}") }&.last
  rescue URI::InvalidURIError
    nil
  end

  def venue_urls
    @venue_urls ||= Place.where.not(url: nil).pluck(:fingerprint, :url).to_h
  end

  def canton_last(locations)
    locations.sort_by { |location| [Location.canton?(location.name) ? 1 : 0, location.name] }
  end

  def event_filter_tag(label, field:, value:, interactive: true, modifier: nil)
    param = field.delete_suffix("[]")

    unless interactive
      return link_to label, events_path(param.to_sym => Array(value), filtered: 1),
                     class: class_names("filter-link", modifier)
    end

    applied = request.query_parameters.except("page")

    matchers =
      case param
      when "g" then { "g" => "g", "q" => "q" }
      else { param => param }
      end
    matched = matchers.to_h { |p, rule| [p, filter_terms_matching(Array(applied[p]), value, param: rule)] }
    active = matched.values.any?(&:present?)

    query = applied.dup
    if active
      matched.each do |p, terms|
        next if terms.empty?
        rest = Array(applied[p]) - terms
        rest.any? ? query[p] = rest : query.delete(p)
      end
    else
      query[param] = Array(applied[param]) + [value.to_s]
    end

    link_to label, events_path(query.merge("filtered" => 1)),
            class: class_names("filter-link", modifier, active: active),
            data: { turbo_frame: "_top" }
  end

  def filter_terms_matching(applied_terms, value, param:)
    case param
    when "q"
      haystack = value.to_s.downcase
      applied_terms.select { |term| haystack.include?(term.to_s.downcase) }
    when "g"
      applied_terms.select { |term| genre_subtree_names(term).include?(value.to_s) }
    else
      applied_terms.select { |term| term.to_s == value.to_s }
    end
  end

  def genre_subtree_names(term)
    (@genre_subtree_names ||= {})[term.to_s] ||= Set.new(Genre.filter_names_for(term))
  end

  def saved_event_ids
    @saved_event_ids ||= Set.new(current_user&.event_saves&.pluck(:event_id))
  end

  def event_saved?(event)
    saved_event_ids.include?(event.id)
  end

  def interest_profile
    @interest_profile ||= InterestProfile.for(current_user)
  end

  def interest_event?(event)
    interest_profile.interesting?(event)
  end

  def interest_why_genre?(event, genre)
    return false unless interest_profile.any?
    return false if applied_filter_term?("g", genre.name)

    interest_profile.why_genres(event).include?(genre)
  end

  def interest_location_names(events)
    return Set.new unless interest_profile.any?

    Array(events)
      .flat_map { |event| interest_profile.why_locations(event) }
      .map(&:name)
      .reject { |name| applied_filter_term?("l", name) }
      .to_set
  end

  def applied_filter_term?(param, value)
    applied = request.query_parameters.except("page")
    matchers = param == "g" ? { "g" => "g", "q" => "q" } : { param => param }
    matchers.any? { |applied_param, rule| filter_terms_matching(Array(applied[applied_param]), value, param: rule).present? }
  end

  def event_save_button(event)
    return unless authenticated?

    saved = event_saved?(event)
    button_tag type: :button,
               class: class_names("event-save", "icon-button", saved: saved),
               'aria-pressed': saved.to_s,
               'aria-label': t("saved_events.toggle"),
               data: { controller: "save", action: "save#toggle",
                       save_event_id_value: event.id, save_saved_value: saved } do
      content_tag(:span, "", class: "save-heart", 'aria-hidden': true)
    end
  end
end
