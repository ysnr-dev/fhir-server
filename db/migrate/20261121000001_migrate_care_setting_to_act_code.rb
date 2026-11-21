# fhir-client の入外区分(入院 / 外来)は、オーダーヘッダ ServiceRequest と報告 DiagnosticReport の
# category に、Encounter.class と同じ HL7 v3 ActCode(IMP / AMB)で持つ(2026-11-21)。それより前の
# クライアントは独自の CodeSystem(prescription-setting / lab-result-setting の inpatient / outpatient)で
# 書いていたので、既存のリソースを v3 ActCode に書き換える。
#
# - 現行の行(service_requests / diagnostic_reports)と履歴(resource_versions)の両方を書き換える。
#   クライアントは新しい表現しか読まないので、履歴から読み出した版や PUT で戻した版も同じ形にそろえる。
# - resource_tokens の category 行も同じ対応で書き換える(token は書き込み時にしか埋まらない)。
# - version_id / last_updated は動かさない(既存の backfill と同じ、静かな正規化)。
# - 対象が「旧 system を持つ行」なので、再実行しても二度目は 0 件(冪等)。
class MigrateCareSettingToActCode < ActiveRecord::Migration[7.0]
  # Table-scoped stubs so the migration never depends on app code.
  class MigrationServiceRequest < ActiveRecord::Base
    self.table_name = "service_requests"
  end

  class MigrationDiagnosticReport < ActiveRecord::Base
    self.table_name = "diagnostic_reports"
  end

  class MigrationResourceVersion < ActiveRecord::Base
    self.table_name = "resource_versions"
  end

  class MigrationResourceToken < ActiveRecord::Base
    self.table_name = "resource_tokens"
  end

  OLD_SYSTEMS = [
    "http://fhir-client.local/CodeSystem/prescription-setting",
    "http://fhir-client.local/CodeSystem/lab-result-setting",
  ].freeze
  ACT_CODE_SYSTEM = "http://terminology.hl7.org/CodeSystem/v3-ActCode".freeze
  ACT_CODES = {
    "inpatient" => { "code" => "IMP", "display" => "inpatient encounter" },
    "outpatient" => { "code" => "AMB", "display" => "ambulatory" },
  }.freeze
  RESOURCE_TYPES = %w[ServiceRequest DiagnosticReport].freeze
  # 無料枠は RAM 512MB なので、jsonb の content を抱え込みすぎないよう小さめのバッチで回す。
  BATCH_SIZE = 200

  def up
    [MigrationServiceRequest, MigrationDiagnosticReport].each { |model| rewrite(with_old_setting(model)) }
    rewrite(with_old_setting(MigrationResourceVersion.where(resource_type: RESOURCE_TYPES)))
    rewrite_tokens
  end

  def down
    # 書き換えた区分と新しいクライアントが書いた区分を区別できないので戻さない。
  end

  private

  def with_old_setting(scope)
    conditions = OLD_SYSTEMS.map { "content @> ?::jsonb" }.join(" OR ")
    scope.where(conditions, *OLD_SYSTEMS.map { |system| { category: [{ coding: [{ system: system }] }] }.to_json })
  end

  def rewrite(scope)
    scope.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each { |row| row.update_columns(content: converted(row.content)) }
    end
  end

  # 対応の無いコード(未選択のまま書かれた空の区分)は Coding ごと落とし、空になった category も落とす。
  def converted(content)
    categories = Array(content["category"]).filter_map do |category|
      next category unless category.is_a?(Hash) && category["coding"].is_a?(Array)

      codings = category["coding"].filter_map { |coding| converted_coding(coding) }
      category.merge("coding" => codings) if codings.any?
    end
    content.merge("category" => categories)
  end

  def converted_coding(coding)
    return coding unless coding.is_a?(Hash) && OLD_SYSTEMS.include?(coding["system"])

    act_code = ACT_CODES[coding["code"]]
    coding.merge("system" => ACT_CODE_SYSTEM, **act_code) if act_code
  end

  def rewrite_tokens
    ACT_CODES.each do |old_code, act_code|
      MigrationResourceToken
        .where(resource_type: RESOURCE_TYPES, param_name: "category", system: OLD_SYSTEMS, code: old_code)
        .update_all(system: ACT_CODE_SYSTEM, code: act_code["code"], updated_at: Time.current)
    end
    MigrationResourceToken.where(resource_type: RESOURCE_TYPES, param_name: "category", system: OLD_SYSTEMS).delete_all
  end
end
