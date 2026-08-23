module Fhir
  # 検索値にタイムゾーンが書かれていないときに使う、このサーバーのローカル
  # タイムゾーン。FHIR の検索仕様は「検索値にタイムゾーンが無ければサーバーの
  # タイムゾーンを使う」と定めている(search.html の date の節)。
  #
  # これが無いと、日付だけの検索値("2026-08-18")を UTC の 1 日として比べることに
  # なり、JST の朝 9 時前に記録された instant が前日に落ちる。クライアントは
  # 「日付を渡すときは必ず ge<当日00:00+09:00> & lt<翌日00:00+09:00> に展開する」
  # という暗黙のルールでこれを避けていたが、書き忘れると静かに 1 日ずれる。
  #
  # 既定は Asia/Tokyo。このサーバーは JP Core / SS-MIX2 / JLAC を前提にした日本の
  # 医療機関向けなので、未設定のまま UTC で解釈して静かにずれるより、正しい既定を
  # 持たせる方が安全。FHIR_LOCAL_TIMEZONE で上書きできる(タイムゾーン名
  # "Asia/Tokyo" か、固定オフセット "+09:00")。
  module LocalTimeZone
    DEFAULT = "Asia/Tokyo".freeze
    OFFSET_PATTERN = /\A[+-]\d{2}:\d{2}\z/.freeze
    UTC = ActiveSupport::TimeZone["UTC"].freeze

    module_function

    # 設定されたゾーン。設定値が解決できないときは UTC(仕様の既定に最も近い、
    # 補正なしの動作)に落として検索自体は動かす。
    def zone
      resolve(ENV["FHIR_LOCAL_TIMEZONE"].presence || DEFAULT) || UTC
    end

    def resolve(value)
      return ActiveSupport::TimeZone[offset_seconds(value)] if value.match?(OFFSET_PATTERN)

      ActiveSupport::TimeZone[value]
    end

    def offset_seconds(value)
      sign = value.start_with?("-") ? -1 : 1
      hours, minutes = value[1..].split(":").map(&:to_i)
      sign * (hours * 3600 + minutes * 60)
    end
  end
end
