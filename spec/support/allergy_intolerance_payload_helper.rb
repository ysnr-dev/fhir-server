module AllergyIntolerancePayloadHelper
  def valid_allergy_intolerance_payload(patient_id:, **overrides)
    {
      "resourceType" => "AllergyIntolerance",
      "identifier" => [{ "system" => "http://example.org/allergy", "value" => "AL1" }],
      "clinicalStatus" => {
        "coding" => [
          { "system" => "http://terminology.hl7.org/CodeSystem/allergyintolerance-clinical", "code" => "active" }
        ]
      },
      "verificationStatus" => {
        "coding" => [
          { "system" => "http://terminology.hl7.org/CodeSystem/allergyintolerance-verification", "code" => "confirmed" }
        ]
      },
      "type" => "allergy",
      "category" => ["medication"],
      "criticality" => "high",
      "code" => {
        "coding" => [
          { "system" => "http://www.nlm.nih.gov/research/umls/rxnorm", "code" => "7980", "display" => "Penicillin" }
        ],
        "text" => "ペニシリン"
      },
      "patient" => { "reference" => "Patient/#{patient_id}" },
      "recordedDate" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include AllergyIntolerancePayloadHelper, type: :request
end
