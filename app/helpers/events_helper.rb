module EventsHelper
  # A filterable term (venue, location, style). In the interactive events list
  # it's a toggle button wired to the filter Stimulus controller; in read-only
  # contexts (e.g. a notification digest) it's a plain link to the filtered list,
  # so green still means "clickable" without needing a live filter form.
  def event_filter_tag(label, field:, value:, interactive: true, active: false, modifier: nil)
    classes = class_names("filter-link", modifier, active: active)

    if interactive
      button_tag label, type: :button, class: classes,
                 data: { action: "filter#toggleFilter", filter_field_name_param: field, filter_value_param: value }
    else
      link_to label, events_path(field.delete_suffix("[]").to_sym => [value]), class: classes
    end
  end
end
