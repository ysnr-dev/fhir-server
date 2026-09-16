# CarePlan は JP Core がプロファイルしていない型なので、Task / Group / Flag と同じく
# 基本 FHIR R4 だけで検証する -- レジストリが指す HL7 の StructureDefinition は
# vendor しておらず Fhir::Profile::Validator は読み飛ばすため、このバリデータが
# 唯一の検査になる。
class CarePlanValidator < ResourceValidator
  PROFILE_LABEL = "FHIR R4".freeze

  # 0..* Reference elements whose containment is what `part-of` / `goal` search on:
  # a non-array here is silently unsearchable rather than obviously broken, so the
  # shape is checked up front(TaskValidator と同じ理由)。
  REFERENCE_ARRAYS = { "partOf" => "part-of", "goal" => "goal" }.freeze

  private

  def validate
    require_field("status", cardinality: "1..1") &&
      validate_binding("status", Fhir::Terminology::CARE_PLAN_STATUS)
    require_field("intent", cardinality: "1..1") &&
      validate_binding("intent", Fhir::Terminology::CARE_PLAN_INTENT)
    validate_codeable_concept_array("category")
    validate_subject
    validate_period("period")
    REFERENCE_ARRAYS.each { |field, param| validate_reference_array(field, param) }
  end

  # CarePlan.subject は 1..1。R4 の対象は Patient|Group で、Group を指す計画は
  # どの患者コンパートメントにも入らない(その分かれ目は書き手の判断なので通す)。
  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"), cardinality: "1..1")

    validate_patient_reference("subject", on_non_patient: :skip)
  end
end
