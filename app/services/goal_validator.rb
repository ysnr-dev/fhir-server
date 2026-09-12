# Goal は JP Core がプロファイルしていない型なので、CarePlan と同じく基本 FHIR R4 だけで
# 検証する -- レジストリが指す HL7 の StructureDefinition は vendor しておらず
# Fhir::Profile::Validator は読み飛ばすため、このバリデータが唯一の検査になる。
class GoalValidator < ResourceValidator
  PROFILE_LABEL = "FHIR R4".freeze

  private

  def validate
    require_field("lifecycleStatus", cardinality: "1..1") &&
      validate_binding("lifecycleStatus", Fhir::Terminology::GOAL_LIFECYCLE_STATUS)
    validate_description
    validate_achievement_status
    validate_categories
    validate_subject
    # start[x] は choice。日付で書かれたときだけ形を見る(契機コードは自由)。
    validate_date("startDate")
    validate_date("statusDate")
  end

  # Goal.description は 1..1 CodeableConcept。目標そのものの文言で、コード無しの
  # text だけでもよい(値集合は example 束縛)。
  def validate_description
    description = payload["description"]
    return unless require_field("description", cardinality: "1..1")

    return if description.is_a?(Hash)

    add_error(code: "structure", diagnostics: "Goal.description must be a CodeableConcept object",
              expression: "Goal.description")
  end

  # Goal.achievementStatus の束縛は preferred なので、HL7 のコードに縛らない
  # (ePath の達成状態のように、ガイドが独自のコード体系を使う)。形だけを見る。
  def validate_achievement_status
    status = payload["achievementStatus"]
    return if status.blank? || status.is_a?(Hash)

    add_error(code: "structure", diagnostics: "Goal.achievementStatus must be a CodeableConcept object",
              expression: "Goal.achievementStatus")
  end

  def validate_categories
    categories = payload["category"]
    return if categories.blank?

    unless categories.is_a?(Array)
      add_error(code: "structure", diagnostics: "Goal.category must be an array",
                expression: "Goal.category")
      return
    end

    return if categories.all? { |category| category.is_a?(Hash) }

    add_error(code: "structure", diagnostics: "Goal.category entries must be CodeableConcept objects",
              expression: "Goal.category")
  end

  # Goal.subject は 1..1。R4 の対象は Patient|Group|Organization で、Patient 以外を
  # 指す目標はどの患者コンパートメントにも入らない。
  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"), cardinality: "1..1")

    validate_patient_reference("subject", on_non_patient: :skip)
  end
end
