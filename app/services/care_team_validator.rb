# CareTeam は JP Core がプロファイルしていない型なので、Group / Flag / CarePlan と同じく
# 基本 FHIR R4 だけで検証する -- レジストリが指す HL7 の StructureDefinition は vendor
# しておらず Fhir::Profile::Validator は読み飛ばすため、このバリデータが唯一の検査になる。
class CareTeamValidator < ResourceValidator
  PROFILE_LABEL = "FHIR R4".freeze

  private

  def validate
    # status は R4 では 0..1 だが、検索の軸(有効なチームだけを引く)なので必須にする。
    require_field("status", cardinality: "1..1") &&
      validate_binding("status", Fhir::Terminology::CARE_TEAM_STATUS)
    validate_codeable_concept_array("category")
    validate_subject
    validate_period("period")
    validate_participants
  end

  # CareTeam.subject は 0..1(Patient | Group)。無ければ組織的なチームで、どの患者
  # コンパートメントにも入らない(NST・ICT などはそれが正しい)。
  def validate_subject
    return if payload["subject"].blank?

    validate_patient_reference("subject", on_non_patient: :skip)
  end

  # participant は 0..* で、検索(`participant`)は member.reference の jsonb 包含に
  # 依存する。配列でないと黙って検索に当たらなくなるので形を見る。
  def validate_participants
    participants = payload["participant"]
    return if participants.nil?

    unless participants.is_a?(Array) && participants.all? { |p| p.is_a?(Hash) }
      add_error(code: "structure", diagnostics: "CareTeam.participant must be an array of BackboneElements",
                expression: "CareTeam.participant")
      return
    end

    participants.each_with_index do |participant, index|
      member = participant["member"]
      next if member.nil?
      next if member.is_a?(Hash) && member["reference"].is_a?(String) && member["reference"].include?("/")

      add_error(code: "value", diagnostics: "CareTeam.participant[#{index}].member.reference must be a '{Type}/{id}' reference",
                expression: "CareTeam.participant[#{index}].member.reference")
    end
  end
end
