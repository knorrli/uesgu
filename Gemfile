source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Web Push (VAPID-signed) notifications for installed PWAs [https://github.com/pushpad/web-push]
gem "web-push", "~> 3.1"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# I18n
gem 'rails-i18n', '~> 8.0.0'

# Genres and Tags for Events
gem 'acts-as-taggable-on'

# Searching and sorting
gem 'ransack'

# Pagination
gem 'kaminari'

# Support for iCalendar exports
gem 'icalendar'

# Combobox UI element for filters. Pinned: we lean on internal markup/behaviour
# (a custom free-text row in the listbox, two prototype overrides in
# filter_controller.js), so a minor bump could break us silently. Bump
# deliberately, not via a stray `bundle update`.
gem "hotwire_combobox", "~> 0.4.0"

# Soft delete
gem 'discard'

# Web Scraping
gem 'mechanize'

# Calendar View
gem 'simple_calendar'

group :development, :test do
  # See https://guides.rubyonrails.org/ndebugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :test do
  # Browser-driven system tests. Cuprite drives the system Chrome over CDP via
  # Ferrum — no chromedriver/Selenium binary or downloaded browser to manage.
  gem "capybara"
  gem "cuprite"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end
