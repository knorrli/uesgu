module Scrapers
  # The outcome of one scraper run, returned by Scrapers::Agent#call. A plain
  # value object so the Agent stays persistence-agnostic (golden tests never
  # touch the DB) — the orchestrator turns this into a ScrapeResult row and uses
  # created_ids to stamp the events with the run that created them.
  Result = Data.define(:seen, :created, :updated, :unchanged, :errored, :discarded, :created_ids)
end
