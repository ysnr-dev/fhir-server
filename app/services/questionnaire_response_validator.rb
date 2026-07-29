# QuestionnaireResponse against the JASPEHR IG v1.0.0 profile
# (http://www.hosp.ncgm.go.jp/JASPEHR/fhir/StructureDefinition/jaspehr-questionnaireresponse).
#
# Cardinality and slicing come from the vendored StructureDefinition
# (Fhir::Profile::Validator). This class adds what that engine cannot express:
# the jsr-1 linkId invariant, the institution-number format constraint on the
# JP eCS extension, the caret-delimited identifier layout the IG describes in
# prose, and reference existence (which profile validation never checks).
class QuestionnaireResponseValidator < ResourceValidator
  PROFILE_LABEL = "JASPEHR".freeze

  INSTITUTION_NUMBER_EXTENSION =
    "http://jpfhir.jp/fhir/clins/Extension/StructureDefinition/JP_eCS_InstitutionNumber".freeze

  private

  def validate
    validate_identifier
    validate_questionnaire
    require_field("status", cardinality: "1..1") &&
      validate_binding("status", Fhir::Terminology::QUESTIONNAIRE_RESPONSE_STATUS)
    validate_subject
    validate_author
    require_field("authored", cardinality: "1..1") && validate_datetime("authored")
    validate_institution_number
    validate_items
  end

  # 1..1 and, per the IG's narrative, three caret-separated parts:
  # 保険医療機関番号10桁 ^ 被保険者個人識別子 ^ 報告単位ID.
  def validate_identifier
    return unless require_field("identifier", cardinality: "1..1")

    value = payload.dig("identifier", "value")
    return unless value.is_a?(String)

    parts = value.split("^", -1)
    return if parts.size == Fhir::Terminology::JASPEHR_QR_IDENTIFIER_PARTS && parts.none?(&:empty?)

    add_error(
      code: "value",
      diagnostics: "QuestionnaireResponse.identifier.value must be '保険医療機関番号^患者ID^報告単位ID' " \
                   "(#{Fhir::Terminology::JASPEHR_QR_IDENTIFIER_PARTS} non-empty caret-separated parts), got '#{value}'",
      expression: "QuestionnaireResponse.identifier.value"
    )
  end

  # A canonical, not a Reference: it may point at a Questionnaire this server
  # does not hold (the IG builds it as "<profile url>/{name}|{version}"), so
  # only the shape is checked, never local existence.
  def validate_questionnaire
    return unless require_field("questionnaire", cardinality: "1..1")

    value = payload["questionnaire"]
    return if value.is_a?(String) && value.match?(%r{\A[a-zA-Z][a-zA-Z0-9+.-]*:}) # absolute URI

    add_error(
      code: "value",
      diagnostics: "QuestionnaireResponse.questionnaire must be an absolute canonical URL, got '#{value}'",
      expression: "QuestionnaireResponse.questionnaire"
    )
  end

  # The profile fixes subject to Reference(Patient), so a non-Patient target is
  # rejected rather than skipped.
  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"),
                                           expression: "QuestionnaireResponse.subject", cardinality: "1..1")

    validate_patient_reference("subject", on_non_patient: :reject)
  end

  # Reference(Practitioner) per the profile. Existence is deliberately not
  # checked: the IG allows the author to be a `contained` Practitioner, which
  # is referenced as "#practitioner" and has no row to look up.
  def validate_author
    return unless require_field("author", value: payload.dig("author", "reference"),
                                          expression: "QuestionnaireResponse.author", cardinality: "1..1")

    reference = payload.dig("author", "reference")
    return if reference.start_with?("#") || reference.match?(%r{\APractitioner/.+\z})

    add_error(
      code: "value",
      diagnostics: "QuestionnaireResponse.author.reference must be 'Practitioner/{id}' or a contained reference, " \
                   "got '#{reference}'",
      expression: "QuestionnaireResponse.author.reference"
    )
  end

  # valid-value-institutionNumberExtension, when the JP eCS extension is present.
  def validate_institution_number
    Array.wrap(payload["extension"]).each_with_index do |extension, index|
      next unless extension.is_a?(Hash) && extension["url"] == INSTITUTION_NUMBER_EXTENSION

      value = extension.dig("valueIdentifier", "value")
      next if value.is_a?(String) && value.match?(Fhir::Terminology::JASPEHR_INSTITUTION_NUMBER_PATTERN)

      add_error(
        code: "invariant",
        diagnostics: "医療機関番号 '#{value}' must be 10 digits: 2-digit prefecture, 1-digit fee schedule class " \
                     "(1|2|3), 7-digit institution code (JASPEHR valid-value-institutionNumberExtension)",
        expression: "QuestionnaireResponse.extension[#{index}].valueIdentifier.value"
      )
    end
  end

  # jsr-1, over the whole item tree (items nest under both `item` and `answer`).
  def validate_items
    walk_items(payload["item"], "QuestionnaireResponse.item")
  end

  def walk_items(items, base_expression)
    return unless items.is_a?(Array)

    items.each_with_index do |item, index|
      next unless item.is_a?(Hash)

      expression = "#{base_expression}[#{index}]"
      validate_link_id(item, expression)

      walk_items(item["item"], "#{expression}.item")
      Array.wrap(item["answer"]).each_with_index do |answer, answer_index|
        next unless answer.is_a?(Hash)

        walk_items(answer["item"], "#{expression}.answer[#{answer_index}].item")
      end
    end
  end

  def validate_link_id(item, expression)
    link_id = item["linkId"]
    return unless require_field("item.linkId", value: link_id, expression: "#{expression}.linkId", cardinality: "1..1")
    return if link_id.is_a?(String) && link_id.match?(Fhir::Terminology::JASPEHR_TOKEN_PATTERN)

    add_error(
      code: "invariant",
      diagnostics: "linkId '#{link_id}' must match #{Fhir::Terminology::JASPEHR_TOKEN_PATTERN.source} (JASPEHR jsr-1)",
      expression: "#{expression}.linkId"
    )
  end
end
