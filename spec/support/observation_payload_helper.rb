module ObservationPayloadHelper
  def valid_observation_payload(subject_id:, **overrides)
    {
      "resourceType" => "Observation",
      "status" => "final",
      "category" => [
        { "coding" => [
          { "system" => "http://terminology.hl7.org/CodeSystem/observation-category",
            "code" => "laboratory", "display" => "Laboratory" }
        ] }
      ],
      "code" => {
        "coding" => [
          { "system" => "http://loinc.org", "code" => "718-7", "display" => "Hemoglobin [Mass/volume] in Blood" }
        ],
        "text" => "ヘモグロビン"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "effectiveDateTime" => "2026-07-19T10:00:00+09:00",
      "valueQuantity" => { "value" => 13.5, "unit" => "g/dL", "system" => "http://unitsofmeasure.org", "code" => "g/dL" }
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include ObservationPayloadHelper, type: :request
end
