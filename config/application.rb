require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Uesgu
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.i18n.default_locale = :de
    config.i18n.available_locales = [:de, :fr, :en]
    config.i18n.fallbacks = [:de]
    config.time_zone = 'Europe/Berlin'
    # config.eager_load_paths << Rails.root.join("extras")

    # Disable CSRF tokens per form because it does not work when turbo is disabled for a form...
    config.action_controller.per_form_csrf_tokens = false

    Rails.application.reloader.to_prepare do
      Dir[Rails.root.join('app/services/scrapers/**/*.rb')].each { |file| require_dependency(file) }
    end

    # Don't generate system test files.
    config.generators.system_tests = nil

    # No background worker — scheduled work runs as Render cron jobs (see
    # render.yaml) and anything enqueued runs inline. Nothing currently enqueues.
    config.active_job.queue_adapter = :inline
  end
end
