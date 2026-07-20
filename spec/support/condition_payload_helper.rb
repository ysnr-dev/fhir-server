module ConditionPayloadHelper
  def valid_condition_payload(subject_id:, **overrides)
    {
      "resourceType" => "Condition",
      "identifier" => [{ "system" => "http://example.org/condition", "value" => "CD1" }],
      "clinicalStatus" => {
        "coding" => [
          { "system" => "http://terminology.hl7.org/CodeSystem/condition-clinical", "code" => "active" }
        ]
      },
      "verificationStatus" => {
        "coding" => [
          { "system" => "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code" => "confirmed" }
        ]
      },
      "category" => [
        { "coding" => [
          { "system" => "http://terminology.hl7.org/CodeSystem/condition-category", "code" => "encounter-diagnosis" }
        ] }
      ],
      "code" => {
        "coding" => [
          { "system" => "http://hl7.org/fhir/sid/icd-10", "code" => "J20.9", "display" => "急性気管支炎" }
        ],
        "text" => "急性気管支炎"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "onsetDateTime" => "2026-07-19T10:00:00+09:00",
      "recordedDate" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include ConditionPayloadHelper, type: :request
end
