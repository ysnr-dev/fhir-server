module PractitionerRolePayloadHelper
  def valid_practitioner_role_payload(overrides = {})
    {
      "resourceType" => "PractitionerRole",
      "identifier" => [
        { "system" => "http://example.org/practitioner-role", "value" => SecureRandom.hex(6) }
      ],
      "active" => true,
      "practitioner" => { "reference" => "Practitioner/#{SecureRandom.uuid}" },
      "organization" => { "reference" => "Organization/#{SecureRandom.uuid}" },
      "code" => [
        { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/practitioner-role", "code" => "doctor" }] }
      ],
      "specialty" => [
        { "coding" => [{ "system" => "http://snomed.info/sct", "code" => "394814009", "display" => "一般内科" }] }
      ]
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include PractitionerRolePayloadHelper, type: :request
end
