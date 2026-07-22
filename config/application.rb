require_relative "boot"

require "rails/all"
# ミドルウェアはautoload前に登録されるため明示require(lib/ はautoload対象外)
require_relative "../lib/middleware/request_size_limiter"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module FhirServer
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # 巨大ボディはボディのパース前に413で拒否する。スタック末尾への追加で
    # SSL/HostAuthorization等の検査後・ルーティング前に位置する
    # (paramsのパースはコントローラ到達時に遅延実行されるため間に合う)。
    config.middleware.use RequestSizeLimiter
  end
end
