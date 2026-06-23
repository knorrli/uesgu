ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "minitest/autorun"
require "minitest/mock" # `stub`/`Mock` explicitly (don't rely on autorun's side-effect load)

# The scraper golden tests are deliberately DB-free (Event + style mapping are
# stubbed), so we don't pull in rails/test_help / the test schema. We do need the
# scraper classes registered with Scrapers::All (populated via the inherited hook),
# so force-load the app.
Rails.application.eager_load!
