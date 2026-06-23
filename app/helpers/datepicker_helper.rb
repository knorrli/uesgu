module DatepickerHelper
  def datepicker_tag(date_range_string)
    button_tag(type: :button, class: "tag active", data: { action: "click->datepicker#removeRange", datepicker_range_param: date_range_string }) do
      content_tag(:div, class: "flex align-baseline gap-small") do
        concat content_tag(:span, nil, class: tag_icon_class(context: "date"))
        concat datepicker_tag_content(date_range_string)
      end
    end
  end

  def datepicker_tag_content(date_range)
    content_tag(:span, date_range_label(date_range))
  end

  # Plain-text label for a date range — a preset's localized name, a single
  # localized date, or a localized "start - end" span. Shared by the date chip
  # (datepicker_tag_content) and the mobile filter sheet's summary.
  def date_range_label(date_range)
    if preset = Datepicker.preset[date_range]
      preset[:label]
    else
      start_date, end_date = date_range.split(" - ").map { |date_string| Time.zone.parse(date_string).to_date }
      if start_date == end_date
        l(start_date, format: :default)
      else
        "#{l(start_date, format: :default)} - #{l(end_date, format: :default)}"
      end
    end
  end
end
