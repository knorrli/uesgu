module EventCapture
  # Reading a printed time into HH:MM. Shared by Normalizer and by the capture screen,
  # whose time field is free text pre-filled from the model.
  #
  # Shape-based on purpose, NOT a list of hour words: the formats that motivated it are
  # the German ones a handful of sample posters happened to carry (20 Uhr, 19:30h,
  # 19.30h), and matching that vocabulary would bake those six posters into the parser
  # when "20h30", "8pm" and a bare "21" are just as likely. So read the leading numbers,
  # treat a trailing marker as noise, and honour only a meridiem — the one marker that
  # changes the value rather than decorating it.
  #
  # Strict about the leading position ("Doors 19:00" is nulled, not salvaged): a null
  # costs one tap, and a wrong time does not announce itself.
  module Clock
    PATTERN = /\A(\d{1,2})\s*(?:[:.h]\s*(\d{2}))?/i
    MERIDIEM = /(?:\d|\s)([ap])\.?m\.?/i
    # "20.08." and "20.08.2026" are dates, and PATTERN reads both as 20:08. A date
    # separator still standing after the minutes is the tell — a real time does not
    # carry one, so nulling here costs nothing and a plausible wrong time costs a lot.
    DATE_TAIL = %r{\A[./]}

    module_function

    # HH:MM, or nil for anything this cannot read with confidence.
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
