module CompositionPayloadHelper
  def valid_composition_payload(subject_id:, author_id: nil, **overrides)
    author_id ||= "unknown"
    {
      "resourceType" => "Composition",
      "identifier" => { "system" => "http://example.org/composition", "value" => "COMP1" },
      "status" => "final",
      "type" => {
        "coding" => [
          { "system" => "http://loinc.org", "code" => "18842-5", "display" => "Discharge summary" }
        ],
        "text" => "退院時サマリ"
      },
      "category" => [
        {
          "coding" => [
            { "system" => "http://loinc.org", "code" => "11488-4", "display" => "Consult note" }
          ]
        }
      ],
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "encounter" => { "reference" => "Encounter/example" },
      "date" => "2026-07-22T10:00:00+09:00",
      "author" => [{ "reference" => "Practitioner/#{author_id}" }],
      "title" => "退院時サマリ",
      "section" => [
        {
          "title" => "主訴",
          "code" => { "coding" => [{ "system" => "http://loinc.org", "code" => "10154-3" }] },
          "text" => { "status" => "generated", "div" => "<div xmlns=\"http://www.w3.org/1999/xhtml\">胸痛</div>" }
        }
      ]
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include CompositionPayloadHelper, type: :request
end
