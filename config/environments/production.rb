require "active_support/core_ext/integer/time"

class RenderLogFormatter < ActiveSupport::Logger::SimpleFormatter
  LEVELS = { "WARN" => "warning", "FATAL" => "critical", "UNKNOWN" => "info" }.freeze

  def call(severity, _timestamp, _progname, msg)
    message = msg.is_a?(String) ? msg : msg.inspect
    "level=#{LEVELS.fetch(severity, severity.downcase)} #{message.strip}\n"
  end
end

Rails.application.configure do
  config.enable_reloading = false

  config.eager_load = true

  config.consider_all_requests_local = false

  config.action_controller.perform_caching = true

  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  config.assume_ssl = true

  config.force_ssl = true

  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.new(
    ActiveSupport::Logger.new(STDOUT).tap { |l| l.formatter = RenderLogFormatter.new }
  )

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  config.silence_healthcheck_path = "/up"

  config.active_support.report_deprecations = false

  config.i18n.fallbacks = true

  config.active_record.dump_schema_after_migration = false

  config.active_record.attributes_for_inspect = [ :id ]

  config.hosts = [
    AppHost::PUBLIC,
    "www.#{AppHost::PUBLIC}",
    AppHost::CODE,
    "www.#{AppHost::CODE}",
    /\A[a-z0-9-]+\.onrender\.com\z/
  ]

  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
