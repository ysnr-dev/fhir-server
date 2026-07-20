module ProcedurePayloadHelper
  def valid_procedure_payload(subject_id:, **overrides)
    {
      "resourceType" => "Procedure",
      "identifier" => [{ "system" => "http://example.org/procedure", "value" => "PR1" }],
      "status" => "completed",
      "category" => {
        "coding" => [
          { "system" => "http://snomed.info/sct", "code" => "387713003", "display" => "Surgical procedure" }
        ]
      },
      "code" => {
        "coding" => [
          { "system" => "http://snomed.info/sct", "code" => "80146002", "display" => "Appendectomy" }
        ],
        "text" => "虫垂切除術"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "performedDateTime" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include ProcedurePayloadHelper, type: :request
end
