module PatientPayloadHelper
  def valid_patient_payload(overrides = {})
    {
      "resourceType" => "Patient",
      "identifier" => [
        { "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => SecureRandom.hex(6) }
      ],
      "active" => true,
      "name" => [
        { "use" => "official", "family" => "山田", "given" => ["太郎"] },
        {
          "extension" => [
            {
              "url" => "http://hl7.org/fhir/StructureDefinition/iso21090-EN-representation",
              "valueCode" => "SYL"
            }
          ],
          "family" => "ヤマダ",
          "given" => ["タロウ"]
        }
      ],
      "gender" => "male",
      "birthDate" => "1990-01-01"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include PatientPayloadHelper, type: :request
end
