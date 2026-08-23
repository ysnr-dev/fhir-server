module Fhir
  # Specimen.accessionIdentifier のサーバー採番。設定された system の identifier が
  # 値なしで作成されるとき、連番から番号を払い出して埋める。
  # ENV["SPECIMEN_ACCESSION_SYSTEM"] が未設定なら何もしない(採番はオプトイン)。
  #
  # 番号は「連番 10 桁ゼロ埋め + チェックデジット(M10W3)1 桁」の 11 桁。
  # M10W3(モジュラス 10 ウェイト 3)は JAN と同じ方式で、右端の桁から 3, 1, 3, ... の
  # 重みを掛けて合計し 10 の補数を取る。バーコードのスキャナ誤読・手入力ミスの検出用。
  # 番号自体に日付や患者番号などの意味は持たせない。
  #
  # クライアント側で採番してから POST すると、conditional create が既存に合流した
  # とき(同時発行の負け側)に番号だけが消費される。作成と同時にサーバーが採番する
  # ことで、番号は実際に作られた Specimen にしか振られない。
  module AccessionAssigner
    SEQUENCE_NAME = "specimen_accession_number_seq".freeze

    module_function

    def assign!(resource_type, payload)
      return unless resource_type == "Specimen" && payload.is_a?(Hash)

      system = ENV["SPECIMEN_ACCESSION_SYSTEM"].presence
      return unless system

      identifier = payload["accessionIdentifier"]
      return unless identifier.is_a?(Hash)
      return unless identifier["system"] == system && identifier["value"].blank?

      identifier["value"] = next_number
    end

    def next_number
      base = format("%010d", next_sequence_value)
      "#{base}#{check_digit(base)}"
    end

    # 連番は Postgres のシーケンスで払い出す(トランザクションを跨いでも重複しない。
    # 作成がロールバックした場合は番号が欠番になるだけで、番号に意味は無いので問題ない)。
    # シーケンスは migration が作るが、schema.rb はシーケンスをダンプしないため、
    # スキーマロードで作った DB (新規の開発環境など)には存在しない。採番はトランザク
    # ション内で走るので「失敗してから作る」はできず(失敗時点でトランザクションが
    # abort する)、先に存在を確かめてから使う。
    def next_sequence_value
      connection = ActiveRecord::Base.connection
      ensure_sequence(connection)
      connection.select_value("SELECT nextval('#{SEQUENCE_NAME}')")
    end

    # 存在確認は毎回行う(カタログ 1 参照で安い)。メモ化すると、テストの
    # トランザクションロールバックで遅延作成した DDL ごと巻き戻ったときに
    # 「作った覚えだけが残る」状態になり、以後の採番が全部失敗する。
    def ensure_sequence(connection)
      exists = connection.select_value(
        "SELECT 1 FROM pg_class WHERE relname = '#{SEQUENCE_NAME}' AND relkind = 'S'"
      )
      connection.execute("CREATE SEQUENCE IF NOT EXISTS #{SEQUENCE_NAME}") unless exists
    end

    def check_digit(digits)
      sum = digits.chars.reverse.each_with_index.sum do |ch, index|
        ch.to_i * (index.even? ? 3 : 1)
      end
      ((10 - sum % 10) % 10).to_s
    end
  end
end
