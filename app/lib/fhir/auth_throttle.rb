module Fhir
  # 認証失敗(401)を IP 単位で数え、閾値超過で一時 ban する(fail2ban 方式)。
  # rack-attack のスロットルはレスポンスステータスを見られないため、
  # 401 を返す側(render_unauthorized / oauth_error)から明示的に記録する。
  # 記録の失敗が認証レスポンス自体を壊さないよう、例外は握ってログに残すだけ。
  module AuthThrottle
    FINDTIME = 1.minute

    module_function

    def max_retries
      Integer(ENV.fetch("FHIR_AUTH_FAIL_MAX", 10))
    end

    def bantime
      Integer(ENV.fetch("FHIR_AUTH_FAIL_BANTIME", 300))
    end

    def register_failure!(ip)
      return unless defined?(Rack::Attack) && Rack::Attack.enabled
      return if ip.blank?

      Rack::Attack::Fail2Ban.filter(
        "auth-fail:#{ip}",
        maxretry: max_retries, findtime: FINDTIME, bantime: bantime
      ) { true }
    rescue StandardError => e
      Rails.logger.warn("AuthThrottle: failed to register auth failure: #{e.class}: #{e.message}")
    end

    def banned?(ip)
      Rack::Attack::Fail2Ban.banned?("auth-fail:#{ip}")
    rescue StandardError
      false
    end
  end
end
