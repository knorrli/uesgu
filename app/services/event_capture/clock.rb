module EventCapture
  module Clock
    PATTERN = /\A(\d{1,2})\s*(?:[:.h]\s*(\d{2}))?/i
    MERIDIEM = /(?:\d|\s)([ap])\.?m\.?/i
    DATE_TAIL = %r{\A[./]}

    module_function

    def parse(value)
      value = value.to_s.strip
      match = value.match(PATTERN)
      return if match.nil? || DATE_TAIL.match?(value[match.end(0)..])

      hour = meridiem_hour(match[1].to_i, value)
      minute = match[2].to_i
      return if hour > 23 || minute > 59

      format("%02d:%02d", hour, minute)
    end

    def meridiem_hour(hour, value)
      case value[MERIDIEM, 1]&.downcase
      when "p" then hour < 12 ? hour + 12 : hour
      when "a" then hour == 12 ? 0 : hour
      else hour
      end
    end
  end
end
