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
    # category は example 束縛なので、CodeableConcept の形だけを見る。
    validate_codeable_concept_array("category")
    validate_subject
    validate_period("period")
  end

  # Flag.subject は 1..1。R4 の対象は Patient に限らない(Location / Group /
  # Organization / Practitioner / PlanDefinition / Medication / Procedure)ため、
  # Patient 以外の参照はそのまま通す(その場合はどの患者コンパートメントにも入らない)。
  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"), cardinality: "1..1")

    validate_patient_reference("subject", on_non_patient: :skip)
  end
end
