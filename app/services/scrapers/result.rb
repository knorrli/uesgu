module Scrapers
  Result = Data.define(:seen, :created, :updated, :unchanged, :errored, :discarded,
                       :created_ids, :robots_note) do
    def initialize(robots_note: nil, **) = super
  end
end
