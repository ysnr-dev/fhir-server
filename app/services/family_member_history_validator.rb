# 家族歴。JP Core の JP_FamilyMemberHistory は基底にほとんど制約を足していないので、
# ここでは R4 の必須要素と required 束縛、検索が前提にする形を検査する。
class FamilyMemberHistoryValidator < ResourceValidator
  private

  def validate
    require_field("status", cardinality: "1..1") &&
      validate_binding("status", Fhir::Terminology::FAMILY_HISTORY_STATUS)
    # relationship は example 束縛(v3 FamilyMember)なので、有無だけを見る。
    require_field("relationship", cardinality: "1..1")
    validate_patient
    validate_datetime("date")
    validate_conditions
  end

  # FamilyMemberHistory.patient is 1..1 Patient.
  def validate_patient
    return unless require_field("patient", value: payload.dig("patient", "reference"), cardinality: "1..1")

    validate_patient_reference("patient", on_non_patient: :reject)
  end

  # condition は 0..* の backbone で、各要素の code は 1..1。`code` 検索はこの配列を
  # 前提に索引するので、配列でない形は弾く。
  def validate_conditions
    conditions = payload["condition"]
    return if conditions.nil?

    unless conditions.is_a?(Array)
      add_error(code: "structure", diagnostics: "FamilyMemberHistory.condition must be an array",
                expression: "FamilyMemberHistory.condition")
      return
    end

    conditions.each_with_index do |condition, index|
      next if condition.is_a?(Hash) && condition["code"].is_a?(Hash) && condition["code"].present?

      add_error(code: "required",
                diagnostics: "FamilyMemberHistory.condition[#{index}].code is required (#{self.class::PROFILE_LABEL}: 1..1)",
                expression: "FamilyMemberHistory.condition[#{index}].code")
    end
  end
end
