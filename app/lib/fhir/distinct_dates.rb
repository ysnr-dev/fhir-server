module Fhir
  # GET /{Type}/$distinct-dates -- ある date/datetime 検索パラメータが取る値の
  # 重複なし集合(新しい順)を返す型レベル operation。
  #
  # クライアントは「患者の診療日の一覧」「直近 N 回分の採取日・測定日時」を作るのに
  # 全リソースを _elements 付きで最後のページまで読んでいた(日付の集合が欲しいだけ
  # なのに本文を全件転送していた)。この operation は日付の列だけを返す。
  #
  # 検索条件は通常の検索パラメータをそのまま受ける(コンパートメント文脈も検索と同じ)。
  # operation 固有のパラメータ:
  #   date-param - 対象の date/datetime 検索パラメータ名。必須。
  #   precision  - "day"(既定): 日付に丸める / "full": datetime の実値を返す。
  #   timezone   - precision=day の日境界(±HH:MM、既定 +00:00)。値は UTC で保存されて
  #                いるため、日本の「診療日」に丸めるには +09:00 を渡す。
  #   limit      - 返す件数の上限(既定 366、最大 1000)。「直近 N 回」用。
  #
  # 応答は Parameters:
  #   parameter[].name = "date"    (valueDate / valueDateTime、降順)
  #   parameter[].name = "undated" (valueBoolean: 値を持たないリソースが 1 件でもあるか。
  #                                 クライアントの「日付なし」グループに対応)
  class DistinctDates
    OPERATION_PARAMS = %w[date-param precision timezone limit].freeze
    TIMEZONE_PATTERN = /\A[+-]\d{2}:\d{2}\z/.freeze
    DEFAULT_LIMIT = 366
    MAX_LIMIT = 1000

    def self.call(resource_type, query_string, context: nil, handling: nil)
      new(resource_type, query_string, context: context, handling: handling).call
    end

    def initialize(resource_type, query_string, context:, handling:)
      @resource_type = resource_type
      @all_clauses = SearchParams.parse(query_string.to_s).clauses
      @context = context
      @handling = handling
    end

    def call
      return invalid("date-param is required") if date_param_name.blank?

      definition = searcher.definition_for(date_param_name)
      unless definition && %i[date datetime].include?(definition[:type])
        return invalid("date-param '#{date_param_name}' is not a date search parameter of #{resource_type}")
      end
      return invalid("timezone must be +HH:MM or -HH:MM") unless timezone_raw.match?(TIMEZONE_PATTERN)
      return invalid("precision must be 'day' or 'full'") unless %w[day full].include?(precision)

      if handling == "strict"
        unsupported = searcher.unsupported_clause_names
        if unsupported.any?
          return invalid("Unsupported search parameter(s): #{unsupported.join(', ')} " \
                         "(rejected because handling=strict was requested)")
        end
      end

      Operation::Result.new(status: :ok, resource: parameters(definition))
    end

    private

    attr_reader :resource_type, :all_clauses, :context, :handling

    # operation 固有のパラメータは検索条件から取り除いて Search に渡す
    # (残すと未知パラメータとして strict で 400 になってしまう)。
    def searcher
      @searcher ||= begin
        search_clauses = all_clauses.reject { |c| OPERATION_PARAMS.include?(c.name) }
        Search.new(resource_type, SearchParams.new(search_clauses), context: context)
      end
    end

    def operation_param(name)
      all_clauses.find { |c| c.name == name }&.values&.first.presence
    end

    def date_param_name
      operation_param("date-param")
    end

    def precision
      operation_param("precision") || "day"
    end

    def timezone_raw
      operation_param("timezone") || "+00:00"
    end

    def limit
      raw = operation_param("limit")
      value = raw ? raw.to_i : DEFAULT_LIMIT
      value = DEFAULT_LIMIT if value <= 0
      [value, MAX_LIMIT].min
    end

    def parameters(definition)
      scope = searcher.filtered_scope
      column = definition[:column]
      undated = scope.where(column => nil).exists?
      dated = scope.where.not(column => nil)

      entries = distinct_values(dated, definition).map { |value| date_entry(value) }
      entries << { "name" => "undated", "valueBoolean" => undated }
      { "resourceType" => "Parameters", "parameter" => entries }
    end

    # DISTINCT + ORDER BY は同じ式でなければならないので、式を 1 度組んで両方に使う。
    # 式は列名(定義由来)と検証済みのオフセット分数だけから成り、クライアント入力の
    # 文字列はそのまま入らない。
    def distinct_values(dated, definition)
      expression = value_expression(dated, definition)
      dated.distinct.order(Arel.sql("#{expression} DESC")).limit(limit).pluck(Arel.sql(expression))
    end

    def value_expression(dated, definition)
      column = "#{dated.model.table_name}.#{definition[:column]}"
      return column if precision == "full"
      # date 型の列はもとから日単位なのでタイムゾーンの補正は掛からない。
      return "DATE(#{column})" if definition[:type] == :date

      # datetime は UTC で保存されている。ローカルの日付に丸めるため、検証済みの
      # オフセットを分に直して足してから DATE() を取る。
      "DATE(#{column} + interval '#{timezone_offset_minutes} minutes')"
    end

    def timezone_offset_minutes
      sign = timezone_raw[0] == "-" ? -1 : 1
      hours, minutes = timezone_raw[1..].split(":").map(&:to_i)
      sign * (hours * 60 + minutes)
    end

    def date_entry(value)
      case value
      when Date then { "name" => "date", "valueDate" => value.iso8601 }
      else { "name" => "date", "valueDateTime" => value.utc.iso8601 }
      end
    end

    def invalid(diagnostics)
      Operation::Result.new(
        status: :bad_request,
        outcome: Fhir::OperationOutcome.single(severity: "error", code: "invalid", diagnostics: diagnostics)
      )
    end
  end
end
