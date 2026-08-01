module RelatedPersonPayloadHelper
  # RelatedPerson.patient is 1..1, so patient_id is required rather than optional.
  # The name array carries both an official name and a kana representation, so
  # name_text exercises all_name_representations the way Patient's fixture does.
  def valid_related_person_payload(patient_id:, **overrides)
    {
      "resourceType" => "RelatedPerson",
      "identifier" => [{ "system" => "http://example.org/related-person", "value" => "RP1" }],
      "active" => true,
      "patient" => { "reference" => "Patient/#{patient_id}" },
      "relationship" => [
        {
          "coding" => [
            { "system" => "http://terminology.hl7.org/CodeSystem/v3-RoleCode", "code" => "MTH", "display" => "mother" }
          ]
        }
      ],
      "name" => [
        { "use" => "official", "family" => "山田", "given" => ["花子"] },
        { "use" => "usual", "text" => "ヤマダ ハナコ" }
      ],
      "gender" => "female",
      "birthDate" => "1970-04-01"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include RelatedPersonPayloadHelper, type: :request
end
