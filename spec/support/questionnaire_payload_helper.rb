module QuestionnairePayloadHelper
  # A JASPEHR-conformant Questionnaire. Note the shape constraints the IG's
  # invariants impose on the item tree: `name` is <= 15 chars from a restricted
  # charset (jsp-5), every linkId uses that same charset (jsp-4), and children of
  # a non-choice item must not carry enableWhen (jsp-9).
  def valid_questionnaire_payload(**overrides)
    {
      "resourceType" => "Questionnaire",
      "url" => "http://example.org/Questionnaire/jaspehr-example",
      "version" => "1.0.0",
      "name" => "ExampleQ",
      "title" => "問診票サンプル",
      "status" => "active",
      "subjectType" => ["Patient"],
      "date" => "2026-07-29T10:00:00+09:00",
      "publisher" => "サンプル病院",
      "code" => [
        { "system" => "http://loinc.org", "code" => "72166-2", "display" => "Tobacco smoking status" }
      ],
      "item" => [
        {
          "linkId" => "group1",
          "type" => "group",
          "text" => "基本情報",
          "item" => [
            { "linkId" => "q1", "type" => "string", "text" => "主訴" },
            { "linkId" => "q2", "type" => "integer", "text" => "発症からの日数" }
          ]
        }
      ]
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include QuestionnairePayloadHelper, type: :request
end
