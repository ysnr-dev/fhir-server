require "digest"

module Fhir
  # GET /{Type}/$next-identifier?system={system} -- その identifier system で次に使える
  # 番号(数値)を払い出す型レベル operation。患者番号のように「連番で振るが、手入力で
  # 飛ばすこともある」識別子のために用意した。
  #
  # クライアントは新規患者の番号を決めるのに、全患者の identifier を _elements 付きで
  # 最後のページまで読んで最大値 + 1 を求め、さらに空き番号を確認する検索を繰り返して
  # いた(最悪 80 往復。同時登録で重複もしうる)。この operation は 1 往復で、同時に
  # 呼んでも同じ番号を 2 度返さない。
  #
  # 払い出しの規則:
  #   - 対象は resource_identifiers の (resource_type, system) が一致する行のうち、値が
  #     10 進の数字だけのもの。英数字の識別子は数えない。
  #   - 削除(論理削除)済みリソースの identifier 行も残っているので、消した患者の番号は
  #     再利用しない。
  #   - 番号は「これまでに払い出した最大値」と「登録済みの最大値」の大きい方 + 1。
  #     払い出した最大値は (resource_type, system) ごとの Postgres シーケンスに持つので、
  #     払い出したが登録されなかった番号は欠番になる(番号に意味は持たせない前提)。
  #     手入力で大きな番号が登録されていれば、その先から続く。
  #   - 比較と更新は advisory lock で直列化する。並行して呼んでも連番になる。
  #
  # 応答は Parameters:
  #   { name: "value",  valueString: "17" }
  #   { name: "system", valueUri: "..." }
  # value は Identifier.value に入れる文字列(先頭ゼロは付けない)。
  class NextIdentifier
    NUMERIC_VALUE = /\A[0-9]{1,18}\z/.freeze

    def self.call(resource_type, system)
      new(resource_type, system).call
    end

    def initialize(resource_type, system)
      @resource_type = resource_type
      @system = system.to_s.strip
    end

    def call
      return invalid("system is required") if system.blank?
      return not_supported unless ResourceRegistry.entry_for(resource_type)

      value = ActiveRecord::Base.transaction { allocate! }
      Operation::Result.new(status: :ok, resource: parameters(value))
    end

    private

    attr_reader :resource_type, :system

    def allocate!
      connection = ActiveRecord::Base.connection
      # トランザクション終了まで保持されるロック。キーは (型, system) から作る。
      connection.execute(
        "SELECT pg_advisory_xact_lock(hashtext(#{connection.quote(lock_key)}))"
      )
      ensure_sequence(connection)

      base = [registered_max, issued_max(connection)].max
      value = base + 1
      connection.execute("SELECT setval('#{sequence_name}', #{value}, true)")
      value
    end

    # 登録済みの最大値。値は文字列なので、数字だけの行に絞ってから数値として比べる
    # ("9" と "10" を文字列で比べると "9" が大きい)。
    def registered_max
      ResourceIdentifier
        .where(resource_type: resource_type, system: system)
        .where("value ~ ?", "^[0-9]{1,18}$")
        .maximum(Arel.sql("value::bigint")).to_i
    end

    # これまでに払い出した最大値。未使用のシーケンスは is_called = false で
    # last_value = 1 なので、その場合は 0 とみなす。
    def issued_max(connection)
      row = connection.select_one("SELECT last_value, is_called FROM #{sequence_name}")
      row["is_called"] ? row["last_value"].to_i : 0
    end

    # schema.rb はシーケンスをダンプしないため、存在確認は毎回行う
    # (Fhir::AccessionAssigner と同じ理由)。
    def ensure_sequence(connection)
      exists = connection.select_value(
        "SELECT 1 FROM pg_class WHERE relname = #{connection.quote(sequence_name)} AND relkind = 'S'"
      )
      connection.execute("CREATE SEQUENCE IF NOT EXISTS #{sequence_name}") unless exists
    end

    # (型, system) ごとのシーケンス。名前は識別子長の制限(63 文字)に収まるよう
    # ハッシュにする。
    def sequence_name
      @sequence_name ||= "next_identifier_#{Digest::SHA256.hexdigest(lock_key)[0, 32]}_seq"
    end

    def lock_key
      "#{resource_type}|#{system}"
    end

    def parameters(value)
      {
        "resourceType" => "Parameters",
        "parameter" => [
          { "name" => "value", "valueString" => value.to_s },
          { "name" => "system", "valueUri" => system }
        ]
      }
    end

    def invalid(diagnostics)
      Operation::Result.new(
        status: :bad_request,
        outcome: Fhir::OperationOutcome.single(severity: "error", code: "invalid", diagnostics: diagnostics)
      )
    end

    def not_supported
      Operation::Result.new(
        status: :not_found,
        outcome: Fhir::OperationOutcome.single(severity: "error", code: "not-supported",
                                               diagnostics: "Resource type '#{resource_type}' is not supported")
      )
    end
  end
end
