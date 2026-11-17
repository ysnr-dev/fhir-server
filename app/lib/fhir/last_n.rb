module Fhir
  # GET /Observation/$lastn -- 検査値・バイタルの「項目(code)ごとの最新 N 件」を
  # 1 回で返す(FHIR R4 の Observation-lastn)。経過表や検査結果の最新値の一覧のように、
  # 項目ごとに検索を繰り返す代わりに使う。
  #
  # 検索条件は通常の Observation の検索パラメータをそのまま受ける(コンパートメント文脈も
  # 検索と同じ)。operation 固有のパラメータ:
  #   max - 項目ごとに返す件数(既定 1、最大 MAX_PER_CODE)。
  #
  # 「同じ項目」は Observation.code の先頭 coding の system|code で判定する。coding が
  # 無ければ code.text で代用する。仕様は「coding のどれかが一致すれば同じ項目」と
  # するが、ここでは先頭の coding だけを見る(1 項目に複数コード体系を併記する場合は、
  # 先頭の coding を揃えておくこと)。
  #
  # 新しさは `date`(effectiveDateTime / effectivePeriod.start)で比べ、値を持たないものは
  # 最後に回す。応答は searchset Bundle で、項目ごとにまとまり、その中は新しい順に並ぶ。
  # `_count` / `_offset` / `_total` / `_summary` / `_elements` / `_include` は検索と同じに効く。
  # 並びは固定なので `_sort` は受け付けない(strict では 400)。
  class LastN
    RESOURCE_TYPE = "Observation".freeze
    OPERATION_PARAMS = %w[max].freeze
    DEFAULT_PER_CODE = 1
    MAX_PER_CODE = 100
    PATH = "#{RESOURCE_TYPE}/$lastn".freeze

    # 列名と固定の JSON パスだけから成る式で、クライアント入力は入らない。
    CODE_KEY_SQL = <<~SQL.squish.freeze
      CASE WHEN observations.code_value IS NOT NULL
           THEN COALESCE(observations.content #>> '{code,coding,0,system}', '') || '|' || observations.code_value
           ELSE 'text:' || COALESCE(observations.code_text, '')
      END
    SQL
    NEWEST_FIRST_SQL = "observations.effective_time DESC NULLS LAST, observations.id ASC".freeze

    def self.call(query_string, base_url:, context: nil, handling: nil)
      new(query_string, base_url: base_url, context: context, handling: handling).call
    end

    def initialize(query_string, base_url:, context:, handling:)
      @search_params = SearchParams.parse(query_string.to_s)
      @base_url = base_url
      @context = context
      @handling = handling
    end

    def call
      return invalid("max must be an integer between 1 and #{MAX_PER_CODE}") unless per_code

      if handling == "strict"
        problems = searcher.unsupported_clause_names.map { |name| "search parameter '#{name}'" }
        problems << "_sort (the result order of $lastn is fixed)" if search_params.sort.present?
        if problems.any?
          return invalid("Unsupported #{problems.join(', ')} (rejected because handling=strict was requested)")
        end
      end

      result = search_result
      included =
        if count_only?
          []
        else
          IncludeResolver.call(
            resource_type: RESOURCE_TYPE, records: result.records, search_params: search_params, context: context
          )
        end
      bundle = BundleBuilder.searchset(
        result: result, base_url: base_url, search_params: search_params, resource_type: RESOURCE_TYPE,
        included: included, shaper: ResourceShaper.build(search_params), path: PATH
      )
      Operation::Result.new(status: :ok, resource: bundle)
    end

    private

    attr_reader :search_params, :base_url, :context, :handling

    # max は検索条件から取り除いて Search に渡す(残すと未知パラメータになる)。ページ送り
    # リンクは元の search_params から組むので、max はリンクに残る。
    def searcher
      @searcher ||= begin
        clauses = search_params.clauses.reject { |c| OPERATION_PARAMS.include?(c.name) }
        Search.new(RESOURCE_TYPE, SearchParams.new(clauses), context: context)
      end
    end

    # nil when the value is not a valid count.
    def per_code
      raw = search_params.clauses_for("max").last&.values&.first
      return DEFAULT_PER_CODE if raw.nil?
      return nil unless raw.match?(/\A\d+\z/)

      value = raw.to_i
      value.between?(1, MAX_PER_CODE) ? value : nil
    end

    def count_only?
      search_params.summary == "count"
    end

    # 項目ごとに新しい順の連番を振り、max 件目までを残す。
    def latest_scope
      ranked = searcher.filtered_scope.select(
        "observations.id, ROW_NUMBER() OVER (PARTITION BY #{CODE_KEY_SQL} ORDER BY #{NEWEST_FIRST_SQL}) AS lastn_rank"
      )
      latest_ids = ::Observation.unscoped.from(ranked, :ranked).where("ranked.lastn_rank <= ?", per_code).select("ranked.id")
      ::Observation.where(id: latest_ids)
    end

    def search_result
      scope = latest_scope
      count = QueryParam.clamp_count(search_params.count, default: Search::DEFAULT_COUNT, max: Search::MAX_COUNT)
      offset = QueryParam.clamp_offset(search_params.offset)
      total = search_params.total_mode == "none" && !count_only? ? nil : scope.count
      records =
        if count_only?
          []
        else
          scope.order(Arel.sql("#{CODE_KEY_SQL} ASC, #{NEWEST_FIRST_SQL}")).limit(count).offset(offset).to_a
        end

      Search::Result.new(records: records, total: total, count: count, offset: offset)
    end

    def invalid(diagnostics)
      Operation::Result.failure(:bad_request, Fhir::OperationOutcome.error("invalid", diagnostics))
    end
  end
end
