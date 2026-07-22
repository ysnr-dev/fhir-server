module DocumentPayloadHelper
  def valid_document_reference_payload(subject_id:, **overrides)
    {
      "resourceType" => "DocumentReference",
      "identifier" => [{ "system" => "http://example.org/document", "value" => "DOC1" }],
      "status" => "current",
      "docStatus" => "final",
      "type" => {
        "coding" => [
          { "system" => "http://loinc.org", "code" => "34133-9", "display" => "Summary of episode note" }
        ],
        "text" => "退院時サマリ"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "date" => "2026-07-22T10:00:00+09:00",
      "content" => [
        {
          "attachment" => {
            "contentType" => "application/pdf",
            "url" => "Binary/example",
            "title" => "退院時サマリ"
          }
        }
      ]
    }.deep_merge(overrides.deep_stringify_keys)
  end

  def valid_binary_payload(**overrides)
    {
      "resourceType" => "Binary",
      "contentType" => "text/plain",
      "data" => Base64.strict_encode64("診療情報テキスト")
    }.merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include DocumentPayloadHelper, type: :request
end
