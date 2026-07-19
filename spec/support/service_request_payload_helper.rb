module ServiceRequestPayloadHelper
  def valid_service_request_payload(subject_id:, **overrides)
    {
      "resourceType" => "ServiceRequest",
      "status" => "active",
      "intent" => "order",
      "code" => {
        "coding" => [{ "system" => "http://snomed.info/sct", "code" => "396550006", "display" => "血液検査" }],
        "text" => "血液検査"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "authoredOn" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include ServiceRequestPayloadHelper, type: :request
end
