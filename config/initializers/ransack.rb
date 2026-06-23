module Arel
  module Predications
    def between_any(other)
      grouping_any :between, other
    end
  end
end


Ransack.configure do |config|
  config.add_predicate "between_any", arel_predicate: "between_any"

  config.add_predicate "between",
    arel_predicate: "between",
    formatter: proc { |v| start_date, end_date = *v.split(" - ").map { |date_string| Time.zone.parse(date_string) }; Range.new(start_date.beginning_of_day, end_date.end_of_day) },
    validator: proc { |v| v.present? },
    compounds: true,
    type: :string
end
