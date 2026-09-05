module FlagPayloadHelper
  CAUTION_SYSTEM = "http://fhir-client.local/CodeSystem/patient-caution".freeze
  CATEGORY_SYSTEM = "http://fhir-client.local/CodeSystem/flag-category".freeze

  def valid_flag_payload(subject_id:, **overrides)
    {
      "resourceType" => "Flag",
      "identifier" => [{ "system" => "http://example.org/flag", "value" => "FL1" }],
      "status" => "active",
      "category" => [
        { "coding" => [{ "system" => CATEGORY_SYSTEM, "code" => "safety", "display" => "安全" }] }
      ],
      "code" => {
        "coding" => [{ "system" => CAUTION_SYSTEM, "code" => "fall", "display" => "転倒リスク" }],
        "text" => "夜間のトイレ移動に付き添いが必要"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "period" => { "start" => "2026-09-01" }
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include FlagPayloadHelper, type: :request
end
