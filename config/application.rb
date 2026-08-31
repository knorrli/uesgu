require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module AppHost
  PUBLIC = ENV.fetch("PUBLIC_HOST", "xn--sgu-goa.ch")
  CODE   = ENV.fetch("CODE_HOST", "uesgu.ch")
end

module Uesgu
  class Application < Rails::Application
    config.load_defaults 8.0

    config.autoload_lib(ignore: %w[assets tasks])

    config.i18n.default_locale = :de
    config.i18n.available_locales = [:de, :fr, :en]
    config.i18n.fallbacks = [:de]
    config.time_zone = "Europe/Berlin"

    config.action_controller.per_form_csrf_tokens = false

    Rails.application.reloader.to_prepare do
      Dir[Rails.root.join("app/services/scrapers/**/*.rb")].each { |file| require_dependency(file) }
    end

    config.generators.system_tests = nil

    config.active_job.queue_adapter = :inline
  end
end
