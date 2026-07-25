module Admin
  # 管理UIのスコープ選択肢。有効なスコープ文字列の列挙可能なリストは
  # Fhir::Scopes には存在せず(正規表現による文法検証のみ)、対応リソース型は
  # Fhir::ResourceRegistry にしかない。クライアント側にハードコードすると
  # リソース型が増えた瞬間にずれるので、サーバーから配る。
  class ScopesController < BaseController
    # 静的な選択肢一覧なので監査しない(ノイズになるだけ)。
    skip_around_action :audit_fhir_request

    def show
      render json: {
        resource_types: resource_type_options,
        # patient/ は書き込みを構造的に拒否する(Fhir::Scopes.valid_patient?)。
        # 選択肢に出しても必ず422になるので出さない。
        system_access: access_options(%w[read write *]),
        patient_access: access_options(%w[read]),
        context_scopes: context_scope_options
      }
    end

    private

    # 先頭のワイルドカードは「すべての診療記録」。UI側でこれを選んだときに
    # 個別型を無効化できるよう、同じ配列の先頭に混ぜて返す。
    def resource_type_options
      (["*"] + Fhir::ResourceRegistry.types).map do |type|
        { type: type, label: Fhir::ScopeLabels.resource(type) }
      end
    end

    def access_options(values)
      values.map { |value| { value: value, label: Fhir::ScopeLabels.access(value) } }
    end

    def context_scope_options
      Fhir::Scopes::CONTEXT_SCOPES.map do |scope|
        { scope: scope, label: Fhir::ScopeLabels.context(scope) }
      end
    end
  end
end
