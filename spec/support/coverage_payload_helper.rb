module CoveragePayloadHelper
  def valid_coverage_payload(beneficiary_id:, payor_id:, **overrides)
    {
      "resourceType" => "Coverage",
      "identifier" => [{ "system" => "http://example.org/coverage", "value" => "CV1" }],
      "status" => "active",
      "type" => {
        "coding" => [
          { "system" => "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code" => "EHCPOL", "display" => "extended healthcare" }
        ],
        "text" => "健康保険"
      },
      "beneficiary" => { "reference" => "Patient/#{beneficiary_id}" },
      "payor" => [{ "reference" => "Organization/#{payor_id}" }],
      "dependent" => "01"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include CoveragePayloadHelper, type: :request
end
