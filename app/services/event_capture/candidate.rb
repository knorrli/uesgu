module EventCapture
  Candidate = Data.define(:title, :subtitle, :subtitle_evidence, :date, :date_evidence, :time,
                          :time_evidence, :place, :place_evidence, :locality, :locality_evidence,
                          :canton, :genres, :source_url, :raw, :issues) do
    def initialize(title: nil, subtitle: nil, subtitle_evidence: nil, date: nil, date_evidence: nil,
                   time: nil, time_evidence: nil, place: nil, place_evidence: nil, locality: nil,
                   locality_evidence: nil, canton: nil, genres: [], source_url: nil, raw: {}, issues: [])
      super
    end

    def past?(today: Time.zone.today) = date.present? && date < today
  end
end
