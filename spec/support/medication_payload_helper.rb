module MedicationPayloadHelper
  def valid_medication_payload(**overrides)
    {
      "resourceType" => "Medication",
      "status" => "active",
      "code" => {
        "coding" => [
          { "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "アムロジピン錠5mg" }
        ],
        "text" => "アムロジピン錠5mg"
      },
      "form" => {
        "coding" => [{ "system" => "urn:oid:1.2.392.100495.20.2.42", "code" => "10", "display" => "錠剤" }]
      }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  # JP_MedicationDispense requires the same rpNumber/orderInRp identifier
  # slices as JP_MedicationRequest (see medication_request_payload_helper.rb),
  # plus a dispensed quantity.
  def valid_medication_dispense_payload(subject_id:, **overrides)
    {
      "resourceType" => "MedicationDispense",
      "status" => "completed",
      "identifier" => [
        { "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/Medication-RPGroupNumber", "value" => "1" },
        { "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/MedicationAdministrationIndex", "value" => "1" }
      ],
      "medicationCodeableConcept" => {
        "coding" => [
          { "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "アムロジピン錠5mg" }
        ],
        "text" => "アムロジピン錠5mg"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "whenHandedOver" => "2026-07-19T10:00:00+09:00",
      "quantity" => { "value" => 14, "unit" => "錠", "system" => "http://unitsofmeasure.org", "code" => "{tablet}" }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  # JP_MedicationAdministration requires the same rpNumber/orderInRp
  # identifier slices as JP_MedicationRequest.
  def valid_medication_administration_payload(subject_id:, **overrides)
    {
      "resourceType" => "MedicationAdministration",
      "status" => "completed",
      "identifier" => [
        { "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/Medication-RPGroupNumber", "value" => "1" },
        { "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/MedicationAdministrationIndex", "value" => "1" }
      ],
      "medicationCodeableConcept" => {
        "coding" => [
          { "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "アムロジピン錠5mg" }
        ],
        "text" => "アムロジピン錠5mg"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "effectiveDateTime" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  def valid_medication_statement_payload(subject_id:, **overrides)
    {
      "resourceType" => "MedicationStatement",
      "status" => "active",
      "medicationCodeableConcept" => {
        "coding" => [
          { "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "アムロジピン錠5mg" }
        ],
        "text" => "アムロジピン錠5mg"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "effectiveDateTime" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include MedicationPayloadHelper, type: :request
end
