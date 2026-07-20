module LocationPayloadHelper
  def valid_location_payload(overrides = {})
    {
      "resourceType" => "Location",
      "identifier" => [
        { "system" => "http://example.org/location", "value" => SecureRandom.hex(6) }
      ],
      "status" => "active",
      "name" => "第1診察室",
      "mode" => "instance",
      "type" => [
        { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v3-RoleCode", "code" => "HOSP" }] }
      ],
      "address" => { "text" => "東京都千代田区1-1-1", "city" => "千代田区", "postalCode" => "100-0001" }
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include LocationPayloadHelper, type: :request
end
