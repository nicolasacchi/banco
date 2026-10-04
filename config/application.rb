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
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Boot-time plumbing lives in lib/banco and is required explicitly (it is used
# before autoloading is available and must not be reloaded).
require_relative "../lib/banco/listeners"
require_relative "../lib/banco/listener_tag"
require_relative "../lib/banco/listener_constraint"
require_relative "../lib/banco/edge_proxy"
require_relative "../lib/banco/token_auth"
require_relative "../lib/banco/append_only"
require_relative "../lib/banco/schemas"
require_relative "../lib/banco/hosts"

module Banco
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks banco harness])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Rome"
    config.i18n.default_locale = :it
    config.i18n.available_locales = %i[it en]

    # Single process, single node: an in-memory cache is enough (no Solid Cache).
    config.cache_store = :memory_store

    # The ledger uses triggers, which schema.rb cannot represent (E-01); the
    # per-database schema_format is set in config/database.yml.

    # One Puma serves three listeners; the tag comes from the accepted socket's
    # local port (D-04). It must be the first middleware.
    config.middleware.insert_before 0, Banco::ListenerTag, allow_test_seam: Rails.env.test?

    # Only the edge proxy is a trusted proxy (D-02); remote_ip is never used for
    # authorization, this only stops Rails from trusting private ranges.
    config.action_dispatch.trusted_proxies = Banco::EdgeProxy.trusted_proxies
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
