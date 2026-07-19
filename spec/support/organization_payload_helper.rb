module OrganizationPayloadHelper
  def valid_organization_payload(overrides = {})
    {
      "resourceType" => "Organization",
      "identifier" => [
        { "system" => "http://jpfhir.jp/fhir/core/IdSystem/insurance-medical-institution-no", "value" => SecureRandom.hex(6) }
      ],
      "active" => true,
      "name" => "サンプル病院"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include OrganizationPayloadHelper, type: :request
end
