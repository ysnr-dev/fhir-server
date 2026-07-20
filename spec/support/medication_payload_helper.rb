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

  def valid_medication_dispense_payload(subject_id:, **overrides)
    {
      "resourceType" => "MedicationDispense",
      "status" => "completed",
      "medicationCodeableConcept" => {
        "coding" => [
          { "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "アムロジピン錠5mg" }
        ],
        "text" => "アムロジピン錠5mg"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "whenHandedOver" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  def valid_medication_administration_payload(subject_id:, **overrides)
    {
      "resourceType" => "MedicationAdministration",
      "status" => "completed",
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
