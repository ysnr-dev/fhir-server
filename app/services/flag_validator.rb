# Flag は JP Core がプロファイルしていない型なので、Group と同じく基本 FHIR R4 だけで
# 検証する -- レジストリが指す HL7 の StructureDefinition は vendor しておらず
# Fhir::Profile::Validator は読み飛ばすため、このバリデータが唯一の検査になる。
class FlagValidator < ResourceValidator
  PROFILE_LABEL = "FHIR R4".freeze

  private

  def validate
    require_field("status", cardinality: "1..1") &&
      validate_binding("status", Fhir::Terminology::FLAG_STATUS)
    require_field("code", cardinality: "1..1")
    validate_categories
    validate_subject
    validate_period
  end

  # Flag.category は 0..* CodeableConcept。値集合は example 束縛なので、コード体系の
  # 中身までは縛らず、CodeableConcept の形だけを見る。
  def validate_categories
    categories = payload["category"]
    return if categories.blank?

    unless categories.is_a?(Array)
      add_error(code: "structure", diagnostics: "Flag.category must be an array",
                expression: "Flag.category")
      return
    end

    return if categories.all? { |category| category.is_a?(Hash) }

    add_error(code: "structure", diagnostics: "Flag.category entries must be CodeableConcept objects",
              expression: "Flag.category")
  end

  # Flag.subject は 1..1。R4 の対象は Patient に限らない(Location / Group /
  # Organization / Practitioner / PlanDefinition / Medication / Procedure)ため、
  # Patient 以外の参照はそのまま通す(その場合はどの患者コンパートメントにも入らない)。
  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"), cardinality: "1..1")

    validate_patient_reference("subject", on_non_patient: :skip)
  end

  def validate_period
    period = payload["period"]
    return if period.blank?

    unless period.is_a?(Hash)
      add_error(code: "structure", diagnostics: "Flag.period must be a Period object",
                expression: "Flag.period")
      return
    end

    validate_datetime("period.start", value: period["start"], expression: "Flag.period.start")
    validate_datetime("period.end", value: period["end"], expression: "Flag.period.end")
  end
end
