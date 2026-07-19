module PractitionerPayloadHelper
  def valid_practitioner_payload(overrides = {})
    {
      "resourceType" => "Practitioner",
      "identifier" => [
        { "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/medicalRegistrationNumber", "value" => SecureRandom.hex(6) }
      ],
      "active" => true,
      "name" => [
        { "use" => "official", "family" => "鈴木", "given" => ["一郎"] },
        {
          "extension" => [
            {
              "url" => "http://hl7.org/fhir/StructureDefinition/iso21090-EN-representation",
              "valueCode" => "SYL"
            }
          ],
          "family" => "スズキ",
          "given" => ["イチロウ"]
        }
      ],
      "gender" => "male",
      "birthDate" => "1980-01-01"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include PractitionerPayloadHelper, type: :request
end
