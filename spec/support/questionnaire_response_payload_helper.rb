module QuestionnaireResponsePayloadHelper
  INSTITUTION_NUMBER_SYSTEM = "http://jpfhir.jp/fhir/core/IdSystem/insurance-medical-institution-no".freeze

  # A JASPEHR-conformant QuestionnaireResponse. `author_id` defaults to a
  # placeholder because the IG allows a contained Practitioner, so the validator
  # checks the reference's shape only and never looks the row up.
  def valid_questionnaire_response_payload(subject_id:, author_id: nil, **overrides)
    author_id ||= "unknown"
    {
      "resourceType" => "QuestionnaireResponse",
      "extension" => [
        {
          "url" => "http://jpfhir.jp/fhir/clins/Extension/StructureDefinition/JP_eCS_InstitutionNumber",
          "valueIdentifier" => { "system" => INSTITUTION_NUMBER_SYSTEM, "value" => "1311234567" }
        }
      ],
      # 保険医療機関番号 ^ 被保険者個人識別子 ^ 報告単位ID
      "identifier" => { "system" => "http://example.org/questionnaire-response", "value" => "1311234567^P0001^R0001" },
      "questionnaire" => "http://example.org/Questionnaire/jaspehr-example|1.0.0",
      "status" => "completed",
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "encounter" => { "reference" => "Encounter/example" },
      "authored" => "2026-07-29T10:00:00+09:00",
      "author" => { "reference" => "Practitioner/#{author_id}" },
      "item" => [
        {
          "linkId" => "group1",
          "text" => "基本情報",
          "item" => [
            { "linkId" => "q1", "text" => "主訴", "answer" => [{ "valueString" => "腹痛" }] },
            { "linkId" => "q2", "text" => "発症からの日数", "answer" => [{ "valueInteger" => 3 }] }
          ]
        }
      ]
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include QuestionnaireResponsePayloadHelper, type: :request
end
