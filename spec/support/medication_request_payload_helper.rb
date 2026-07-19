module MedicationRequestPayloadHelper
  def valid_medication_request_payload(subject_id:, **overrides)
    {
      "resourceType" => "MedicationRequest",
      "identifier" => [
        { "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/Medication-RPGroupNumber", "value" => "1" },
        { "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/MedicationAdministrationIndex", "value" => "1" }
      ],
      "status" => "active",
      "intent" => "order",
      "medicationCodeableConcept" => {
        "coding" => [
          { "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "アムロジピン錠5mg" }
        ],
        "text" => "アムロジピン錠5mg"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "authoredOn" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include MedicationRequestPayloadHelper, type: :request
end
