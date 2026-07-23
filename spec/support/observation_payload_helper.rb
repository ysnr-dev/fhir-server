module ObservationPayloadHelper
  def valid_observation_payload(subject_id:, **overrides)
    {
      "resourceType" => "Observation",
      "status" => "final",
      # JP_Observation_Common requires a category slice ("first") coded solely
      # from JP_SimpleObservationCategory_CS -- it must be its own array item,
      # not mixed into the same CodeableConcept as the base HL7 coding below,
      # since the slice's own definition fixes every coding.system within a
      # matched item to the JP code system.
      "category" => [
        { "coding" => [
          { "system" => "http://terminology.hl7.org/CodeSystem/observation-category",
            "code" => "laboratory", "display" => "Laboratory" }
        ] },
        { "coding" => [
          { "system" => "http://jpfhir.jp/fhir/core/CodeSystem/JP_SimpleObservationCategory_CS",
            "code" => "laboratory" }
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
