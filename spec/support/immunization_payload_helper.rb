module ImmunizationPayloadHelper
  def valid_immunization_payload(patient_id:, **overrides)
    {
      "resourceType" => "Immunization",
      "identifier" => [{ "system" => "http://example.org/immunization", "value" => "IM1" }],
      "status" => "completed",
      "vaccineCode" => {
        "coding" => [
          { "system" => "http://hl7.org/fhir/sid/ndc", "code" => "49281-0215-88", "display" => "COVID-19 vaccine" }
        ],
        "text" => "新型コロナワクチン"
      },
      "patient" => { "reference" => "Patient/#{patient_id}" },
      "occurrenceDateTime" => "2026-07-19T10:00:00+09:00",
      "lotNumber" => "LOT-123"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include ImmunizationPayloadHelper, type: :request
end
