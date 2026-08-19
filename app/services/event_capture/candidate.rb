module EventCapture
  # One event the model read out of one image — 0..n of these per input, because a
  # poster can advertise two concerts. A plain value object: nothing here is
  # persisted, and the verify screen (#106) is what turns an accepted candidate
  # into an Event.
  #
  # `raw` keeps every value the normalizer refused, keyed by field, and `issues`
  # says why. A rejected value is never silently dropped — a human completes a null
  # in one tap, but they can only do that if they can still see what the model
  # claimed.
  Candidate = Data.define(:title, :date, :date_evidence, :time, :place, :place_evidence,
                          :locality, :canton, :genres, :source_url, :raw, :issues) do
    def initialize(title: nil, date: nil, date_evidence: nil, time: nil, place: nil,
                   place_evidence: nil, locality: nil, canton: nil, genres: [],
                   source_url: nil, raw: {}, issues: [])
      super
    end

    # Computed, never asked of the model: it got is_past wrong every time it tried.
    def past?(today: Time.zone.today) = date.present? && date < today
  end
end
