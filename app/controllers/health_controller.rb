# LB/監視用のヘルスチェック。ApplicationController を継承しないことで
# rescue_from(OperationOutcome化)・認証・監査の対象から構造的に外す。
# SSLリダイレクト・HostAuthorization・rack-attack もそれぞれ /up を除外している。
class HealthController < ActionController::API
  def show
    ActiveRecord::Base.connection_pool.with_connection { |conn| conn.select_value("SELECT 1") }
    render json: { status: "ok" }
  rescue StandardError
    # 障害内容は外部に漏らさない(詳細はログ/モニタリングで追う)
    render json: { status: "error" }, status: :service_unavailable
  end
end
