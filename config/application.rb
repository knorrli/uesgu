require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Single source of truth for our two domains. The public site is served from the
# umlaut domain üsgu.ch, which arrives on the wire as its punycode form
# (AppHost::PUBLIC) — the canonical host everything 301s to. uesgu.ch
# (AppHost::CODE) is the ASCII twin used for email and shareable/copyable links;
# it 301s back to PUBLIC preserving path + query (see config/routes.rb).
#
# ENV-backed so a domain move is a one-place change, with the current values as
# defaults. Defined here rather than in an initializer because config/environments
# and config/routes.rb read these constants during boot, before initializers run.
module AppHost
  PUBLIC = ENV.fetch("PUBLIC_HOST", "xn--sgu-goa.ch") # üsgu.ch, punycode-encoded
  CODE   = ENV.fetch("CODE_HOST", "uesgu.ch")         # ASCII twin for mail + links
end

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
