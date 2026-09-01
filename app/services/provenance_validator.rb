# Provenance は JP Core / JASPEHR がプロファイルしていないので、Group / Task と同じく
# 基底 FHIR R4 だけで検証する(registry が指す HL7 の StructureDefinition は vendor に
# 無いため Fhir::Profile::Validator は素通りし、このバリデータだけが働く)。
#
# 用途は代行入力と承認(README「Provenance の例」):
#   代行入力 … agent[] に author(指示した医師)と enterer(入力した本人、onBehalfOf で指示者を指す)
#   承認     … agent[] に verifier を足し、signature[] に署名を残す
class ProvenanceValidator < ResourceValidator
  PROFILE_LABEL = "FHIR R4".freeze

  private

  def validate
    validate_target
    require_field("recorded", cardinality: "1..1") && validate_instant("recorded")
    validate_agents
    validate_occurred
    validate_signatures
    validate_entities
  end

  # target は「この活動が生んだ・更新したリソース」。1..* で参照先の型は問わないので、
  # 存在確認まではしない(異種のうえ 1 オーダーで数件並ぶため。他の型の参照と同じ扱い)。
  def validate_target
    targets = payload["target"]
    return unless require_field("target", cardinality: "1..*")

    unless targets.is_a?(Array)
      add_error(code: "structure", diagnostics: "Provenance.target must be an array",
                expression: "Provenance.target")
      return
    end

    targets.each_with_index { |target, index| validate_target_entry(target, index) }
  end

  def validate_target_entry(target, index)
    expression = "Provenance.target[#{index}].reference"
    reference = target.is_a?(Hash) ? target["reference"] : nil
    if reference.blank?
      add_error(code: "required",
                diagnostics: "Provenance.target.reference is required (#{PROFILE_LABEL}: 1..1)",
                expression: expression)
      return
    end

    # バージョン付き参照は FHIR 上は正当だが、このサーバーの参照検索・_include は
    # 格納文字列の完全一致なので、"ServiceRequest/1/_history/2" は ?target=ServiceRequest/1
    # からも _revinclude=Provenance:target からも静かに外れる。拒否はせず警告に留める。
    return unless reference.include?("/_history/")

    add_warning(code: "informational",
                diagnostics: "Provenance.target.reference '#{reference}' is version-specific; " \
                             "this server matches references literally, so it will not be found by " \
                             "?target= or _revinclude=Provenance:target. Store an unversioned reference.",
                expression: expression)
  end

  def validate_agents
    agents = payload["agent"]
    return unless require_field("agent", cardinality: "1..*")

    unless agents.is_a?(Array)
      add_error(code: "structure", diagnostics: "Provenance.agent must be an array",
                expression: "Provenance.agent")
      return
    end

    agents.each_with_index { |agent, index| validate_agent(agent, index) }
  end

  def validate_agent(agent, index)
    unless agent.is_a?(Hash) && agent.dig("who", "reference").present?
      add_error(code: "required",
                diagnostics: "Provenance.agent.who.reference is required (#{PROFILE_LABEL}: 1..1)",
                expression: "Provenance.agent[#{index}].who.reference")
      return
    end

    # agent.type は extensible binding なので、外れたコードは拒否せず警告にする
    # (施設独自の役割を載せる余地を残す)。
    code = Fhir::FieldExtractor.coding_code(agent["type"])
    return if code.blank? || Fhir::Terminology::PROVENANCE_AGENT_TYPE.include?(code)

    add_warning(code: "code-invalid",
                diagnostics: "Provenance.agent.type '#{code}' is outside the recommended value set: " \
                             "#{Fhir::Terminology::PROVENANCE_AGENT_TYPE.join(', ')}",
                expression: "Provenance.agent[#{index}].type")
  end

  # occurred[x] は choice 型。両方書くと「いつ起きたか」が二重になる。
  def validate_occurred
    if payload.key?("occurredDateTime") && payload.key?("occurredPeriod")
      add_error(code: "structure",
                diagnostics: "Provenance.occurred[x] is a choice: set occurredDateTime or occurredPeriod, not both",
                expression: %w[Provenance.occurredDateTime Provenance.occurredPeriod])
    end

    validate_datetime("occurredDateTime")
  end

  # 承認の署名。type(署名の目的)・when(署名時刻)・who(署名者)が揃っていないと、
  # 「誰がいつ何を承認したか」にならない。
  def validate_signatures
    signatures = payload["signature"]
    return if signatures.blank?

    unless signatures.is_a?(Array)
      add_error(code: "structure", diagnostics: "Provenance.signature must be an array",
                expression: "Provenance.signature")
      return
    end

    signatures.each_with_index { |signature, index| validate_signature(signature, index) }
  end

  def validate_signature(signature, index)
    base = "Provenance.signature[#{index}]"
    unless signature.is_a?(Hash)
      add_error(code: "structure", diagnostics: "Provenance.signature must contain Signature elements",
                expression: base)
      return
    end

    codes = Array(signature["type"]).select { |coding| coding.is_a?(Hash) && coding["code"].present? }
    if codes.empty?
      add_error(code: "required",
                diagnostics: "Provenance.signature.type is required (#{PROFILE_LABEL}: 1..*) and each Coding needs a code",
                expression: "#{base}.type")
    end

    if signature["when"].blank?
      add_error(code: "required",
                diagnostics: "Provenance.signature.when is required (#{PROFILE_LABEL}: 1..1)",
                expression: "#{base}.when")
    else
      validate_instant("signature.when", value: signature["when"], expression: "#{base}.when")
    end

    return if signature.dig("who", "reference").present?

    add_error(code: "required",
              diagnostics: "Provenance.signature.who.reference is required (#{PROFILE_LABEL}: 1..1)",
              expression: "#{base}.who.reference")
  end

  def validate_entities
    entities = payload["entity"]
    return if entities.blank?

    unless entities.is_a?(Array)
      add_error(code: "structure", diagnostics: "Provenance.entity must be an array",
                expression: "Provenance.entity")
      return
    end

    entities.each_with_index { |entity, index| validate_entity(entity, index) }
  end

  def validate_entity(entity, index)
    base = "Provenance.entity[#{index}]"
    unless entity.is_a?(Hash)
      add_error(code: "structure", diagnostics: "Provenance.entity must contain elements",
                expression: base)
      return
    end

    # entity.role は required binding なので、外れたコードはエラー(agent.type と違う)。
    role = entity["role"]
    if role.blank?
      add_error(code: "required",
                diagnostics: "Provenance.entity.role is required (#{PROFILE_LABEL}: 1..1)",
                expression: "#{base}.role")
    else
      validate_binding("entity.role", Fhir::Terminology::PROVENANCE_ENTITY_ROLE,
                       value: role, expression: "#{base}.role")
    end

    return if entity.dig("what", "reference").present?

    add_error(code: "required",
              diagnostics: "Provenance.entity.what.reference is required (#{PROFILE_LABEL}: 1..1)",
              expression: "#{base}.what.reference")
  end
end
