class EventDays
  attr_reader :dates

  def initialize(events, today: Date.current)
    @dates = events.reorder(nil).distinct.pluck(:start_date).sort
    @today = today
  end

  def any? = dates.any?

  def default
    dates.find { |date| date >= today } || dates.last
  end

  def resolve(requested)
    return default if requested.nil?

    dates.find { |date| date >= requested } || dates.last
  end

  def before(day)
    dates.reverse_each.find { |date| date < day }
  end

  def after(day)
    dates.find { |date| date > day }
  end

  private

  attr_reader :today
end
