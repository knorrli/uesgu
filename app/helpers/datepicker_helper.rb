module DatepickerHelper
  def date_range_label(date_range)
    Datepicker.preset.fetch(date_range)[:label]
  end
end
