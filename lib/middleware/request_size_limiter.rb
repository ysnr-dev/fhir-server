# Content-Length が上限(FHIR_MAX_BODY_BYTES、デフォルト10MB)を超える
# リクエストボディをパース前に 413 で拒否する。Puma は Transfer-Encoding:
# chunked をデチャンクして CONTENT_LENGTH を設定するため、Content-Length の
# 検査だけで足りる。上限は Binary/DocumentReference の添付を想定した値。
class RequestSizeLimiter
  DEFAULT_MAX_BYTES = 10 * 1024 * 1024

  # テストから差し替えられるようクラス属性にしている(Fhir::Auth と同じ流儀)
  class << self
    attr_writer :max_bytes

    def max_bytes
      @max_bytes ||= Integer(ENV.fetch("FHIR_MAX_BODY_BYTES", DEFAULT_MAX_BYTES))
    end
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) if env["CONTENT_LENGTH"].to_i <= self.class.max_bytes

    body = Fhir::OperationOutcome.single(
      severity: "error",
      code: "too-long",
      diagnostics: "Request body exceeds the maximum allowed size of #{self.class.max_bytes} bytes"
    ).to_json
    [413, { "content-type" => "application/fhir+json" }, [body]]
  end
end
