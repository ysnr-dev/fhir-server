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
  #   timezone   - precision=day の日境界(±HH:MM)。既定はサーバーのローカル
  #                タイムゾーン(Fhir::LocalTimeZone)。値は UTC で保存されているため、
  #                日本の「診療日」に丸めるには +09:00 相当が要る。
  #   limit      - 返す件数の上限(既定 366、最大 1000)。「直近 N 回」用。
  #   count      - "true" なら日付ごとの件数も返す(月カレンダーの空き枠数バッジなど)。
  #
  # 応答は Parameters:
  #   parameter[].name = "date"    (valueDate / valueDateTime、降順)
  #   parameter[].name = "undated" (valueBoolean: 値を持たないリソースが 1 件でもあるか。
  #                                 クライアントの「日付なし」グループに対応)
  #
  # count=true のときは、Parameters の「value と part は排他」という不変条件があるため
  # date の各要素が part 形式になる:
  #   { name: "date", part: [{ name: "value", valueDate: … }, { name: "count", valueInteger: … }] }
  class DistinctDates
    OPERATION_PARAMS = %w[date-param precision timezone limit count].freeze
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

    # 指定が無ければサーバーのローカルタイムゾーンの、この時点でのオフセットを使う
    # (検索の日付解釈と同じ基準に揃える)。
    def timezone_raw
      operation_param("timezone") || LocalTimeZone.zone.now.formatted_offset
    end

    def count?
      operation_param("count") == "true"
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

      entries = date_entries(dated, definition)
      entries << { "name" => "undated", "valueBoolean" => undated }
      { "resourceType" => "Parameters", "parameter" => entries }
    end

    def date_entries(dated, definition)
      expression = value_expression(dated, definition)
      return distinct_values(dated, expression).map { |value| date_entry(value) } unless count?

      counts_by_value(dated, expression).map do |value, count|
        { "name" => "date",
          "part" => [date_entry(value).merge("name" => "value"),
                     { "name" => "count", "valueInteger" => count }] }
      end
    end

    # DISTINCT + ORDER BY は同じ式でなければならないので、式を 1 度組んで両方に使う。
    # 式は列名(定義由来)と検証済みのオフセット分数だけから成り、クライアント入力の
    # 文字列はそのまま入らない。
    def distinct_values(dated, expression)
      dated.distinct.order(Arel.sql("#{expression} DESC")).limit(limit).pluck(Arel.sql(expression))
    end

    # GROUP BY で日付ごとの件数を数える。ORDER BY / LIMIT は DISTINCT のときと同じ。
    def counts_by_value(dated, expression)
      dated.group(Arel.sql(expression)).order(Arel.sql("#{expression} DESC")).limit(limit).count
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
